*******************************************************************************;
* PROGRAM DETAILS                                                             *;
*   Filename: SRPM_PHQ9_QA.sas                                                *;
*   Purpose:  This program assesses the availability of PHQ item #9 data for  *;
*             the previously identified SRPM VDW-based denominator of mental  *;
*             health–related outpatient clinic visits. The program addresses  *;
*             the following questions:                                        *;
*             1 How many person-dates are associated with multiple qualifying *;
*               SRPM VDW encounters?                                          *;
*             2 How are VDW encounters being matched to PHQ item #9 scores?   *;
*   Updated:  01 February 2017                                                *;
*******************************************************************************;
* UPDATE HISTORY                                                              *;
*   Date      Comment                                                         *;
*   ========================================================================= *;
*   20170201  Initial GitHub version finalized.                               *;
*******************************************************************************;

*******************************************************************************;
* START OF EDIT SECTION                                                       *;
*******************************************************************************;

*------------------------------------------------------------------------------;
* %include full path to local StdVars file.                                    ;
*------------------------------------------------------------------------------;
%include "\\path\StdVars.sas";

*------------------------------------------------------------------------------;
* %let root = location to which you extracted this program.                    ;
*------------------------------------------------------------------------------;
%let root = \\path\SRPM_PHQ9_QA;

*------------------------------------------------------------------------------;
* %let startdt = either 01JAN2009 or DDMONYYYY-formatted date of local Epic    ;
* implementation, whichever happened more recently.                            ;
*------------------------------------------------------------------------------;
%let startdate = 01JAN2009;

*------------------------------------------------------------------------------;
* %let denom = location of SRPM_DENOM_FULL data set. (Should be in /LOCAL      ;
* subfolder from SRPM_DENOM program package.)                                  ;
*------------------------------------------------------------------------------;
%let denom = \\path\SRPM_DENOM\LOCAL;

*------------------------------------------------------------------------------;
* %let cesrpro = location of PHQ9_CESR_PRO data set described in README.md.    ;
*------------------------------------------------------------------------------;
%let cesrpro = \\path\phq9_cesr_pro;

*------------------------------------------------------------------------------;
* %let item9_ids = comma-separated list of QUESTION_ID values (in quotes) to   ;
* identify PHQ item #9 scores in CESR PRO_SURVEY_RESPONSES table or            ;
* PHQ9_CESR_PRO data set described above. E.g., %let item9_ids = '123', '456'  ;
*------------------------------------------------------------------------------;
%let item9_ids = ;

*******************************************************************************;
* END OF EDIT SECTION                                                         *;
*******************************************************************************;

data _null_;
  x = index("&root", "SRPM_PHQ9_QA");
  if x = 0 then call symput('root', strip("&root" || "/SRPM_PHQ9_QA"));
run;

proc datasets kill lib=work memtype=data nolist;
quit;

%macro dsdelete(dslist /* pipe-delimited list */);
  %do i = 1 %to %sysfunc(countw(&dslist, |));
    %let dsname = %scan(&dslist, &i, |);
    %if %sysfunc(exist(&dsname)) = 1 %then %do;
      proc sql;
        drop table &dsname;
      quit;
    %end;
  %end;
%mend dsdelete;

options errors=0 formchar="|----|+|---+=|-/\<>*" mprint nocenter nodate nofmterr
  nomlogic nonumber nosymbolgen
;

ods results off;

ods listing;

title;

footnote;

%let filedate = %sysfunc(today(), yymmddn8.);

%let dispdate = %sysfunc(today(), mmddyys10.);

resetline;

proc printto log="&root/LOCAL/SRPM_PHQ9_QA_&_siteabbr..log" new;
run;

*******************************************************************************;
* Obtain valid PHQ item #9 responses between start date and 06/30/2015.       *;
*******************************************************************************;
libname cesrpro "&cesrpro";

data phq_item9;
    set cesrpro.phq9_cesr_pro;
    where response_date between "&startdate"d and "30JUN2015"d
      and question_id in (&item9_ids)
      and strip(response_text) in ('0', '1', '2', '3')
    ;
  MRN_DATE = catx('_', mrn, put(response_date, yymmddn8.));
  keep QUESTION_ID MRN RESPONSE_DATE RESPONSE_TIME RESPONSE_TEXT ENC_ID
    PROVIDER PAT_ENC_CSN_ID MRN_DATE
  ;
run;

*******************************************************************************;
* Create a crosswalk of distinct VDW ENC_ID to Clarity PECI combinations.     *;
* Determine which VDW encounters stand alone as the only qualifying visit per *;
* day and which occur on the same day as other qualifying visits.             *;
*******************************************************************************;
libname denom "&denom";

proc sql;
  create table enc_peci_raw as
  select distinct enc_id
    , enc_peci as pat_enc_csn_id  
    , catx('_', mrn, put(adate, yymmddn8.)) as mrn_date
    , adate
    , provider
  from denom.srpm_denom_full_&_siteabbr
  where enc_peci ^= .
  union
  select distinct enc_id
    , px_peci as pat_enc_csn_id  
    , catx('_', mrn, put(adate, yymmddn8.)) as mrn_date
    , adate
    , provider
  from denom.srpm_denom_full_&_siteabbr
  where px_peci ^= .
  union
  select distinct enc_id
    , dx_peci as pat_enc_csn_id  
    , catx('_', mrn, put(adate, yymmddn8.)) as mrn_date
    , adate
    , provider
  from denom.srpm_denom_full_&_siteabbr
  where dx_peci ^= .
  union
  select distinct enc_id
    , . as pat_enc_csn_id  
    , catx('_', mrn, put(adate, yymmddn8.)) as mrn_date
    , adate
    , provider
  from denom.srpm_denom_full_&_siteabbr
  where enc_peci = dx_peci = px_peci = .
  order by enc_id
    , pat_enc_csn_id
    , mrn_date
  ;

  create table enc_peci_dedup as
  select distinct enc_id
    , pat_enc_csn_id
    , mrn_date
    , adate
    , provider
  from enc_peci_raw
  order by enc_id
    , pat_enc_csn_id
  ;

  create table enc_per_day as
  select mrn_date
    , count(distinct enc_id) as daily_enc_count
  from enc_peci_dedup
  group by mrn_date
  ;

  create table enc_peci_master as
  select a.*
    , b.daily_enc_count
  from enc_peci_dedup as a
    inner join enc_per_day as b
    on a.mrn_date = b.mrn_date
  ;
quit;

%dsdelete(enc_peci_raw|enc_per_day|enc_peci_dedup)

*******************************************************************************;
* Match 1. For standalone VDW encounters (i.e., single qualifying visit per   *;
* date) that match to item #9 on VDW ENC_ID, keep the item #9 score with      *;
* latest date/time stamp per VDW encounter.                                   *;
*******************************************************************************;
proc sql;
  create table match1_all as
  select distinct e.enc_id
    , e.mrn_date
    , e.provider
    , e.daily_enc_count
    , p.response_text
    , p.response_date
    , p.response_time
    , case
        when e.enc_id = p.enc_id 
          and missing(e.enc_id) = missing(p.enc_id) = 0
          then 1
        else 0
      end as match1 length=3
  from enc_peci_master as e
    left join phq_item9 as p
      on e.enc_id = p.enc_id
      and missing(e.enc_id) = missing(p.enc_id) = 0
  where e.daily_enc_count = 1
  order by enc_id
    , response_date
    , response_time
  ;
quit;

data match1_dedup;
  set match1_all;
  by enc_id response_date response_time;
  if last.enc_id;
run;

*******************************************************************************;
* Match 2. For remaining standalone VDW encounters (i.e., single qualifying   *;
* visit per date) that match to item #9 on Epic/Clarity PECI, keep available  *;
* item #9 score with latest date/time stamp per VDW encounter.                *;
*******************************************************************************;
proc sql;
  create table match2_all as
  select distinct m.enc_id
    , m.mrn_date
    , m.provider
    , m.daily_enc_count
    , p.response_text
    , p.response_date
    , p.response_time
    , case
        when e.pat_enc_csn_id = p.pat_enc_csn_id
          and missing(e.pat_enc_csn_id) = missing(p.pat_enc_csn_id) = 0
          then 1
        else 0
      end as match2 length=3
  from match1_dedup as m
    inner join enc_peci_master as e
      on m.enc_id = e.enc_id
    left join phq_item9 as p
      on e.pat_enc_csn_id = p.pat_enc_csn_id
      and missing(e.pat_enc_csn_id) = missing(p.pat_enc_csn_id) = 0
  where m.match1 = 0
  order by enc_id
    , response_date
    , response_time
  ;
quit;

data match2_dedup;
  set match2_all;
  by enc_id response_date response_time;
  if last.enc_id;
run;

*******************************************************************************;
* Match 3. For remaining standalone VDW encounters (i.e., single qualifying   *;
* visit per date) that match to item #9 on MRN+Date+Provider, keep available  *;
* item #9 score with latest date/time stamp per VDW encounter.                *;
*******************************************************************************;
proc sql;
  create table match3_all as
  select distinct m.enc_id
    , m.mrn_date
    , m.provider
    , m.daily_enc_count
    , p.response_text
    , p.response_date
    , p.response_time
    , case
        when e.mrn_date = p.mrn_date
          and e.provider = p.provider
          and missing(e.provider) = missing(p.provider) = 0
          then 1
        else 0
      end as match3 length=3
  from match2_dedup as m
    inner join enc_peci_master as e
      on m.enc_id = e.enc_id
    left join phq_item9 as p
      on e.mrn_date = p.mrn_date
      and e.provider = p.provider
      and missing(e.provider) = missing(p.provider) = 0
  where m.match2 = 0
  order by enc_id
    , response_date
    , response_time
  ;
quit;

data match3_dedup;
  set match3_all;
  by enc_id response_date response_time;
  if last.enc_id;
run;

*******************************************************************************;
* Match 4. For remaining standalone VDW encounters (i.e., single qualifying   *;
* visit per date) that match to item #9 on MRN+Date, keep available item #9   *;
* score with latest date/time stamp per VDW encounter.                        *;
*******************************************************************************;
proc sql;
  create table match4_all as
  select distinct m.enc_id
    , m.mrn_date
    , m.provider
    , m.daily_enc_count
    , p.response_text
    , p.response_date
    , p.response_time
    , case
        when e.mrn_date = p.mrn_date then 1
        else 0
      end as match4 length=3
  from match3_dedup as m
    inner join enc_peci_master as e
      on m.enc_id = e.enc_id
    left join phq_item9 as p
      on e.mrn_date = p.mrn_date
  where m.match3 = 0
  order by enc_id
    , response_date
    , response_time
  ;
quit;

data match4_dedup;
  set match4_all;
  by enc_id response_date response_time;
  if last.enc_id;
run;

*******************************************************************************;
* Match 5. For VDW encounters that occur on the same day as other qualifying  *;
* VDW encounters, match to PHQ item #9 on VDW ENC_ID where possible. In case  *;
* of duplicates, keep available item #9 score with latest date/time stamp per *;
* VDW encounter.                                                              *;
*******************************************************************************;
proc sql;
  create table match5_all as
  select distinct e.enc_id
    , e.mrn_date
    , e.provider
    , e.daily_enc_count
    , p.response_text
    , p.response_date
    , p.response_time
    , case
        when e.enc_id = p.enc_id and missing(e.enc_id) = missing(p.enc_id) = 0 
          then 1
        else 0
      end as match5 length=3
  from enc_peci_master as e
    left join phq_item9 as p
      on e.enc_id = p.enc_id
      and missing(e.enc_id) = missing(p.enc_id) = 0
  where e.daily_enc_count > 1
  order by enc_id
    , response_date
    , response_time
  ;
quit;

data match5_dedup;
  set match5_all;
  by enc_id response_date response_time;
  if last.enc_id;
run;

*******************************************************************************;
* Match 6. For remaining VDW encounters that occur on the same day as other   *;
* qualifying VDW encounters, match to PHQ item #9 on Epic/Clarity PECI where  *;
* available. In case of duplicates, keep the most recently entered item #9    *;
* score per VDW encounter.                                                    *;
*******************************************************************************;
proc sql;
  create table match6_all as
  select distinct m.enc_id
    , m.mrn_date
    , e.provider
    , m.daily_enc_count
    , p.response_text
    , p.response_date
    , p.response_time
    , case
        when e.pat_enc_csn_id = p.pat_enc_csn_id
          and missing(e.pat_enc_csn_id) = missing(p.pat_enc_csn_id) = 0
          then 1
        else 0
      end as match6 length=3
  from match5_dedup as m
    inner join enc_peci_master as e
      on m.enc_id = e.enc_id
    left join phq_item9 as p
      on e.pat_enc_csn_id = p.pat_enc_csn_id
      and missing(e.pat_enc_csn_id) = missing(p.pat_enc_csn_id) = 0
  where m.match5 = 0
  order by enc_id
    , response_date
    , response_time
  ;
quit;

data match6_dedup;
  set match6_all;
  by enc_id response_date response_time;
  if last.enc_id;
run;

*******************************************************************************;
* Match 7. For remaining VDW encounters that occur on the same day as other   *;
* qualifying VDW encounters, match to PHQ item #9 on MRN+Date+Provider where  *;
* available. In case of duplicates, keep the most recently entered item #9    *;
* score per VDW encounter.                                                    *;
*******************************************************************************;
proc sql;
  create table match7_all as
  select distinct m.enc_id
    , m.mrn_date
    , e.provider
    , m.daily_enc_count
    , p.response_text
    , p.response_date
    , p.response_time
    , case
        when e.mrn_date = p.mrn_date
          and e.provider = p.provider
          and missing(e.provider) = missing(p.provider) = 0
          then 1
        else 0
      end as match7 length=3
  from match6_dedup as m
    inner join enc_peci_master as e
      on m.enc_id = e.enc_id
    left join phq_item9 as p
      on e.mrn_date = p.mrn_date
      and e.provider = p.provider
      and missing(e.provider) = missing(p.provider) = 0
  where m.match6 = 0
  order by enc_id
    , response_date
    , response_time
  ;
quit;

data match7_dedup;
  set match7_all;
  by enc_id response_date response_time;
  if last.enc_id;
run;

*******************************************************************************;
* Match 8. For remaining VDW encounters that occur on the same day as other   *;
* qualifying VDW encounters, see how many unique item #9 scores are available *;
* when matching on just MRN + Date. If only one item #9 score is available,   *;
* match it to all qualifying visits from the date. If multiple item #9 scores *;
* are available, do not match any of them, as we cannot determine which visit *;
* each score belongs to.                                                      *;
*******************************************************************************;
proc sql;
  create table match8_all as
  select distinct m.enc_id
    , m.mrn_date
    , m.provider
    , m.daily_enc_count
    , p.response_text
    , p.response_date
    , p.response_time
    , case when e.mrn_date = p.mrn_date then 1 else 0 end as match8 length=3
  from match7_dedup as m
    inner join enc_peci_master as e
      on m.enc_id = e.enc_id
    left join phq_item9 as p
      on e.mrn_date = p.mrn_date
  where m.match7 = 0
  order by enc_id
    , response_date
    , response_time
  ;

  create table match8_item9 as
  select mrn_date
    , match8
    , count(distinct response_text) as unique_item9
  from match8_all
  group by mrn_date
    , match8
  ;

  create table match8_flag_dup as
  select a.*
    , i.unique_item9
  from match8_all as a
    inner join match8_item9 as i
      on a.mrn_date = i.mrn_date
  order by enc_id
    , response_date
    , response_time
  ;
quit;

data match8_dedup;
  set match8_flag_dup;
  by enc_id response_date response_time;
  match8 = unique_item9;
  if last.enc_id;
run;

data combine_all;
  set match1_dedup (in=a where=(match1 = 1))
    match2_dedup (in=b where=(match2 = 1))
    match3_dedup (in=c where=(match3 = 1))
    match4_dedup (in=d)
    match5_dedup (in=e where=(match5 = 1))
    match6_dedup (in=f where=(match6 = 1))
    match7_dedup (in=g where=(match7 = 1))
    match8_dedup (in=h)
  ;
  if a then item9_match = '1';
    else if b then item9_match = '2';
    else if c then item9_match = '3';
    else if d then do;
      if match4 = 1 then item9_match = '4';
        else item9_match = 'X';
    end;
    else if e then item9_match = '5';
    else if f then item9_match = '6';
    else if g then item9_match = '7';
    else if h then do;
      if match8 = 1 then item9_match = '8';
        else if match8 > 1 then item9_match = '9';
        else item9_match = 'X';
    end;
  * Clear matches that are too "fuzzy." *;
  if item9_match = '9' then do;
    response_date = .;
    response_time = .;
    response_text = '';
  end;
  drop match1-match8;
run;

proc format;
  value daily_enc_count
    1 = 'Single'
    2-high = 'Multiple'
  ;
  value $ item9_match
    '1', '5' = 'VDW Encounter ID'
    '2', '6' = 'Epic Encounter ID'
    '3', '7' = 'MRN + Date + Provider'
    '4', '8' = 'MRN + Date (Acceptable Match)'
    '9' = 'MRN + Date (Too Fuzzy, Do Not Use)'
    'X' = 'None'
  ;
  value mask
    0<-<&lowest_count = "<&lowest_count"
    other = [comma10.]
  ;
run;

proc sql;
  create table encs_per_day as
  select daily_enc_count
    , count(distinct mrn_date) as person_dates
  from combine_all
  group by 1
  ;
quit;

ods listing close;

ods escapechar='^';

options center orientation=landscape;

ods pdf file="&root/SHARE/SRPM_PHQ9_QA_&_siteabbr..pdf"
  style=pearl notoc
;

proc tabulate data=encs_per_day style=[cellwidth=1in];
  title1 "SRPM PHQ Item #9 QA: &_sitename";
  title2 "How many person-dates are associated with >1 qualifying visit*?";
  class daily_enc_count / style=[cellwidth=1in];
  classlev daily_enc_count / style=[cellwidth=1in font_weight=medium];
  var person_dates;
  keyword n pctn / style=[font_weight=medium];
  table daily_enc_count='' all='Total' 
    , person_dates='Person-Dates' * (sum='N'*f=mask. pctsum='%'*f=6.1)
    / box=[label='Same-Day Visits' style=[vjust=bottom just=left]]
  ;
  footnote1 "Filename: &root/SHARE/SRPM_PHQ9_QA_&_siteabbr..pdf";
  footnote2 "Page ^{thispage} of ^{lastpage} · Prepared on &dispdate";
run;

ods pdf text='^{newline 2}^{nbspace 95}*Visit = VDW encounter';

proc tabulate data=combine_all;
  title1 "SRPM PHQ Item #9 QA: &_sitename";
  title2 "How are denominator visits* linked to PHQ item #9 scores?";
  class daily_enc_count;
  class item9_match / preloadfmt;
  classlev daily_enc_count item9_match / style=[font_weight=medium];
  format daily_enc_count daily_enc_count. item9_match $item9_match.;
  keyword n / style=[cellwidth=.8in font_weight=medium];
  keyword colpctn rowpctn / style=[cellwidth=.6in font_weight=medium];
  tables item9_match='' all='Total Visits'
    , (daily_enc_count='Visit Type**' all='Total Visits')
      * (n='N'*f=mask. colpctn='Col %'*f=6.1 rowpctn='Row %'*f=6.1)
    / box=[label='Item #9 Match Type' style=[vjust=bottom just=left]]
      misstext='0' printmiss
  ;
  footnote1 "Filename: &root/SHARE/SRPM_PHQ9_QA_&_siteabbr..pdf";
  footnote2 "Page ^{thispage} of ^{lastpage} · Prepared on &dispdate";
run;

ods pdf text='^{newline 2}*Visit = VDW encounter';

ods pdf text='**Single = visit is the only qualifying encounter on
 a given person-date; Multiple = visit co-occurs with other qualifying
 encounters on the same person-date'
;

ods pdf close;

proc printto;
run;

*******************************************************************************;
* END OF PROGRAM                                                              *;
*******************************************************************************;
