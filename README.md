# Suicide Risk Prediction Model (SRPM)
## PHQ-9 Data Quality Assurance (QA)

The [Mental Health Research Network (MHRN)](http://hcsrn.org/mhrn/en/) Suicide Risk Prediction Model (SRPM) encompasses the following major programming tasks:

1. Identify denominator (code written in [Base SAS®](http://www.sas.com/en_us/software/base-sas.html))
    1. **Recommended: Perform quality checks on [Patient Health Questionnaire (PHQ-9)](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC1495268/) data (code written in Base SAS)**
2. Create analytic data set (code written in Base SAS)
3. Implement model (code written in [R](https://www.r-project.org/))

In addition to this README, the srpm-phq9-qa repository contains the following materials that were used to assess PHQ item #9 data within the MHRN.

* **SAS program:** SRPM_PHQ9_QA.sas
    * **Details:** Developed in SAS 9.4 for use in the [HCSRN VDW](http://www.hcsrn.org/en/Tools%20&%20Materials/VDW/) programming environment
    * **Purpose:** PHQ item #9 asks, "Over the last two weeks, how often have you been bothered by thoughts that you would be better off dead, or of hurting yourself in some way?" A patient's response to item #9 is an especially important predictor of suicide risk. As such, this program assesses the availability of PHQ item #9 data for the VDW-based denominator of mental health–related outpatient clinic visits (identified in step 1 above). The program addresses the following questions:
	    1. How many person-dates are associated with multiple qualifying VDW encounters?
		2. How are VDW encounters being matched to PHQ item #9 scores?
    * **Input SAS data sets:** 
	    * SRPM_DENOM_FULL_SITE.sas7bdat
            * This data set should have been produced by SRPM_DENOM.sas and stored in the accompanying /LOCAL subdirectory. More information available in the [MHResearchNetwork/sprm-denom](https://github.com/MHResearchNetwork/srpm-denom) repository.
		    * Note: SITE = local site abbreviation as implemented in VDW StdVars &_siteabbr macro variable
		* PHQ9_CESR_PRO.sas7bdat
		    * This data set must be created from local PHQ-9 item-level response data and stored in a location accessible to the program.
            * The required data elements, shown below in Table 1, represent a simplified version of the Kaiser Permanente CESR data model PRO_SURVEY_RESPONSES table (PRO = Patient Reported Outcomes). 
    * **Other dependencies:** StdVars.sas; local modifications in introductory edit section
    * **Output files:**
        * /LOCAL/SRPM_PHQ9_QA_SITE.log – SAS log file
        * /SHARE/SRPM_PHQ9_QA_SITE.pdf – Table for local review. Small cell sizes suppressed per local implementation of VDW StdVars &lowest_count macro variable.
* **Subdirectory /LOCAL:** Stores SAS log file for local review
* **Subdirectory /RETURN:** Stores summary PDF file (which was originally intended for return to lead site)

The basic procedure to generate the PHQ item #9 quality assurance analysis is as follows:

1. Prepare the PHQ9_CESR_PRO SAS data set as specified above and in Table 1 below.
2. Extract repository contents to local directory of choice.
3. Open SRPM_PHQ9_QA.sas and complete initial %include and %let statements as directed in program header.
4. Submit modified program.
5. After program execution is complete, ensure that aforementioned log and PDF files have been output to the appropriate subdirectories.
6. Review /LOCAL/SRPM_PHQ9_QA_SITE.log for errors.
7. If log file is clean, review /SHARE/SRPM_PHQ9_QA_SITE.pdf to better understand the availability of PHQ item #9 data for your SRPM denominator.

**Table 1. PHQ9_CESR_PRO data dictionary**

Name | Type | Description
--- | --- | ---
MRN | Character | Patient-level identifier, for use in linking to VDW-based denominator
QUESTION_ID | Character | PHQ item-level identifier, for use in differentiating between items 1–9. Valid values vary by site. Can be set to FLO_MEAS_ID or other Epic/Clarity-based differentiator if appropriate. Programmer will need to know which value(s) correspond to item #9 specifically.
RESPONSE_DATE | SAS date | Date of PHQ response (e.g., Clarity PAT_ENC.CONTACT_DATE if PHQ data are sourced from Epic)
RESPONSE_TIME | SAS datetime | Date/time of PHQ-9 response (e.g., Clarity PAT_ENC.ENTRY_TIME or IP_FLWSHT_MEAS.RECORDED_TIME). For use in selecting most recent available score.
RESPONSE_TEXT | Character | PHQ item score. Valid values are 0, 1, 2, 3, and blank (' ').
ENC_ID | Character or numeric, per local VDW specifications | VDW-based encounter ID, if already linked to PHQ response data. If unavailable, set to blank (' ') if your VDW ENC_ID is a character variable or null (.) if numeric.
PROVIDER | Character | Provider identifier, for use in linking to VDW-based denominator. If PHQ data are sourced from Epic, this field can be set to Clarity PAT_ENC.VISIT_PROV_ID assuming that ID can be linked directly to VDW ENCOUNTER.PROVIDER.
