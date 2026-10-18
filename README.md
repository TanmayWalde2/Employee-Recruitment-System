# Employee Recruitment System (MySQL version)

Stack: HTML/CSS/JS frontend - Python Flask backend - MySQL 8.0+ database

## Setup
1. MySQL Workbench -> File > Open SQL Script -> `recruitment_db.sql` -> click the lightning bolt (runs all).
   This creates database `recruitment_db` with tables, views, triggers and sample data.
2. Open `app.py` and put your MySQL password in `DB_CONFIG`.
3. `pip install flask mysql-connector-python`
4. `python app.py`  then open http://127.0.0.1:5000

## Database
Tables: department, vacancy, applicant, qualification, interviewer, application, interview, selection
Triggers: block closed vacancy / low experience; interview -> "Interview Scheduled"; selection -> final status
Views: v_vacancy, v_qualification, v_interviewer, v_application, v_interview, v_selection, v_ranking
