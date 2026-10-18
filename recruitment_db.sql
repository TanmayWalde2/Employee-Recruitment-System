-- =====================================================================
-- Employee Recruitment System  -  MySQL 8.0+  (run whole file in Workbench)
-- WARNING: drops and recreates the database recruitment_db every time.
-- =====================================================================
DROP DATABASE IF EXISTS recruitment_db;
CREATE DATABASE recruitment_db CHARACTER SET utf8mb4;
USE recruitment_db;

CREATE TABLE department (
  dept_id INT AUTO_INCREMENT PRIMARY KEY,
  name    VARCHAR(100) NOT NULL UNIQUE
) ENGINE=InnoDB;

CREATE TABLE vacancy (
  vacancy_id     INT AUTO_INCREMENT PRIMARY KEY,
  title          VARCHAR(120) NOT NULL,
  dept_id        INT NOT NULL,
  openings       INT NOT NULL,
  salary         DECIMAL(12,2) NOT NULL,
  min_experience INT NOT NULL DEFAULT 0,
  last_date      DATE NOT NULL,
  status         ENUM('Open','Closed') NOT NULL DEFAULT 'Open',
  CONSTRAINT chk_openings CHECK (openings > 0),
  CONSTRAINT chk_salary   CHECK (salary >= 0),
  CONSTRAINT chk_minexp   CHECK (min_experience >= 0),
  CONSTRAINT fk_vac_dept FOREIGN KEY (dept_id) REFERENCES department(dept_id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE applicant (
  applicant_id     INT AUTO_INCREMENT PRIMARY KEY,
  name             VARCHAR(100) NOT NULL,
  email            VARCHAR(120) NOT NULL UNIQUE,
  phone            VARCHAR(20),
  experience_years INT NOT NULL DEFAULT 0,
  address          VARCHAR(255),
  CONSTRAINT chk_exp CHECK (experience_years >= 0)
) ENGINE=InnoDB;

CREATE TABLE qualification (
  qual_id      INT AUTO_INCREMENT PRIMARY KEY,
  applicant_id INT NOT NULL,
  degree       VARCHAR(120) NOT NULL,
  institution  VARCHAR(150) NOT NULL,
  `year`       INT NOT NULL,
  percentage   DECIMAL(5,2),
  CONSTRAINT chk_year CHECK (`year` BETWEEN 1980 AND 2100),
  CONSTRAINT chk_pct  CHECK (percentage BETWEEN 0 AND 100),
  CONSTRAINT fk_qual_app FOREIGN KEY (applicant_id) REFERENCES applicant(applicant_id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE interviewer (
  interviewer_id INT AUTO_INCREMENT PRIMARY KEY,
  name           VARCHAR(100) NOT NULL,
  designation    VARCHAR(100),
  dept_id        INT NULL,
  CONSTRAINT fk_intr_dept FOREIGN KEY (dept_id) REFERENCES department(dept_id) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE application (
  application_id INT AUTO_INCREMENT PRIMARY KEY,
  applicant_id   INT NOT NULL,
  vacancy_id     INT NOT NULL,
  applied_on     DATE NOT NULL,
  status         ENUM('Applied','Shortlisted','Interview Scheduled','Selected','Rejected')
                 NOT NULL DEFAULT 'Applied',
  CONSTRAINT uq_app UNIQUE (applicant_id, vacancy_id),
  CONSTRAINT fk_ap_applicant FOREIGN KEY (applicant_id) REFERENCES applicant(applicant_id) ON DELETE CASCADE,
  CONSTRAINT fk_ap_vacancy   FOREIGN KEY (vacancy_id)   REFERENCES vacancy(vacancy_id)     ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE interview (
  interview_id   INT AUTO_INCREMENT PRIMARY KEY,
  application_id INT NOT NULL,
  interviewer_id INT NOT NULL,
  interview_date DATE NOT NULL,
  `round`        ENUM('Screening','Technical','HR') NOT NULL DEFAULT 'Technical',
  score          INT,
  remarks        VARCHAR(255),
  CONSTRAINT chk_score CHECK (score BETWEEN 0 AND 10),
  CONSTRAINT fk_int_app  FOREIGN KEY (application_id) REFERENCES application(application_id) ON DELETE CASCADE,
  CONSTRAINT fk_int_intr FOREIGN KEY (interviewer_id) REFERENCES interviewer(interviewer_id)
) ENGINE=InnoDB;

CREATE TABLE selection (
  selection_id   INT AUTO_INCREMENT PRIMARY KEY,
  application_id INT NOT NULL UNIQUE,
  decision       ENUM('Selected','Rejected') NOT NULL,
  offered_salary DECIMAL(12,2),
  joining_date   DATE,
  decided_on     DATE NOT NULL,
  CONSTRAINT fk_sel_app FOREIGN KEY (application_id) REFERENCES application(application_id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE INDEX idx_app_vacancy   ON application(vacancy_id);
CREATE INDEX idx_app_applicant ON application(applicant_id);
CREATE INDEX idx_int_app       ON interview(application_id);

-- ---------------------------- VIEWS ----------------------------------
CREATE VIEW v_vacancy AS
SELECT v.vacancy_id, v.title, v.dept_id, v.openings, v.salary, v.min_experience,
       v.last_date, v.status, d.name AS department,
       (SELECT COUNT(*) FROM application a WHERE a.vacancy_id = v.vacancy_id) AS applications,
       (SELECT COUNT(*) FROM application a WHERE a.vacancy_id = v.vacancy_id AND a.status = 'Selected') AS filled
FROM vacancy v JOIN department d ON d.dept_id = v.dept_id;

CREATE VIEW v_qualification AS
SELECT q.qual_id, q.applicant_id, q.degree, q.institution, q.`year`, q.percentage, a.name AS applicant
FROM qualification q JOIN applicant a ON a.applicant_id = q.applicant_id;

CREATE VIEW v_interviewer AS
SELECT i.interviewer_id, i.name, i.designation, i.dept_id, d.name AS department
FROM interviewer i LEFT JOIN department d ON d.dept_id = i.dept_id;

CREATE VIEW v_application AS
SELECT ap.application_id, ap.applicant_id, ap.vacancy_id, ap.applied_on, ap.status,
       a.name AS applicant, v.title AS vacancy,
       CONCAT(a.name, ' - ', v.title) AS label
FROM application ap
JOIN applicant a ON a.applicant_id = ap.applicant_id
JOIN vacancy   v ON v.vacancy_id   = ap.vacancy_id;

CREATE VIEW v_interview AS
SELECT i.interview_id, i.application_id, i.interviewer_id, i.interview_date, i.`round`,
       i.score, i.remarks, va.label AS application, it.name AS interviewer
FROM interview i
JOIN v_application va ON va.application_id = i.application_id
JOIN interviewer it   ON it.interviewer_id = i.interviewer_id;

CREATE VIEW v_selection AS
SELECT s.selection_id, s.application_id, s.decision, s.offered_salary, s.joining_date, s.decided_on,
       va.label AS application, va.applicant, va.vacancy
FROM selection s JOIN v_application va ON va.application_id = s.application_id;

-- Ranking: average interview score per application
CREATE VIEW v_ranking AS
SELECT va.application_id, va.applicant, va.vacancy, va.status,
       ROUND(AVG(i.score), 2) AS avg_score, COUNT(i.interview_id) AS rounds
FROM v_application va JOIN interview i ON i.application_id = va.application_id
GROUP BY va.application_id, va.applicant, va.vacancy, va.status
ORDER BY avg_score DESC;

-- ---------------------------- TRIGGERS -------------------------------
DELIMITER $$

CREATE TRIGGER trg_check_application BEFORE INSERT ON application
FOR EACH ROW
BEGIN
  DECLARE v_status VARCHAR(10);
  DECLARE v_min INT;
  DECLARE a_exp INT;
  SELECT status, min_experience INTO v_status, v_min FROM vacancy WHERE vacancy_id = NEW.vacancy_id;
  SELECT experience_years INTO a_exp FROM applicant WHERE applicant_id = NEW.applicant_id;
  IF v_status = 'Closed' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'This vacancy is closed';
  END IF;
  IF a_exp < v_min THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Applicant does not meet minimum experience';
  END IF;
END$$

CREATE TRIGGER trg_interview_status AFTER INSERT ON interview
FOR EACH ROW
BEGIN
  UPDATE application SET status = 'Interview Scheduled'
  WHERE application_id = NEW.application_id AND status IN ('Applied','Shortlisted');
END$$

CREATE TRIGGER trg_selection_insert AFTER INSERT ON selection
FOR EACH ROW
BEGIN
  UPDATE application SET status = NEW.decision WHERE application_id = NEW.application_id;
END$$

CREATE TRIGGER trg_selection_update AFTER UPDATE ON selection
FOR EACH ROW
BEGIN
  UPDATE application SET status = NEW.decision WHERE application_id = NEW.application_id;
END$$

DELIMITER ;

-- ---------------------------- SAMPLE DATA ----------------------------
INSERT INTO department(name) VALUES ('Engineering'),('Human Resources'),('Finance'),('Marketing');

INSERT INTO vacancy(title,dept_id,openings,salary,min_experience,last_date,status) VALUES
 ('Java Developer',1,2,600000,1,'2026-12-31','Open'),
 ('Data Analyst',1,1,550000,0,'2026-12-15','Open'),
 ('HR Executive',2,1,400000,2,'2026-11-30','Open'),
 ('Accountant',3,1,420000,3,'2026-09-30','Closed');

INSERT INTO applicant(name,email,phone,experience_years,address) VALUES
 ('Aarav Sharma','aarav@mail.com','9876500001',2,'Pune'),
 ('Neha Patil','neha@mail.com','9876500002',1,'Nagpur'),
 ('Rohan Deshmukh','rohan@mail.com','9876500003',0,'Mumbai'),
 ('Sana Khan','sana@mail.com','9876500004',3,'Nashik');

INSERT INTO qualification(applicant_id,degree,institution,`year`,percentage) VALUES
 (1,'B.E. Information Technology','COEP Pune',2022,78.5),
 (2,'B.Tech Computer Science','VNIT Nagpur',2023,82),
 (3,'B.Sc Statistics','Mumbai University',2025,74),
 (4,'MBA (HR)','Symbiosis',2021,70.2),
 (1,'HSC','Pune Board',2018,85);

INSERT INTO interviewer(name,designation,dept_id) VALUES
 ('Dr. Mehta','Engineering Manager',1),('Priya Nair','HR Manager',2),('S. Iyer','Senior Developer',1);

INSERT INTO application(applicant_id,vacancy_id,applied_on,status) VALUES
 (1,1,'2026-10-01','Shortlisted'),(2,1,'2026-10-02','Applied'),
 (3,2,'2026-10-03','Applied'),(4,3,'2026-10-04','Applied');

INSERT INTO interview(application_id,interviewer_id,interview_date,`round`,score,remarks) VALUES
 (1,1,'2026-10-10','Technical',8,'Strong in Java and DBMS'),
 (1,2,'2026-10-12','HR',9,'Good communication'),
 (4,2,'2026-10-11','HR',7,'Relevant experience');

INSERT INTO selection(application_id,decision,offered_salary,joining_date,decided_on) VALUES
 (1,'Selected',620000,'2026-12-01','2026-10-14');
