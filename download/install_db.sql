
-- start work with our database xaps
USE xaps;
-- Tables with no or minimal foreign keys
DROP TABLE IF EXISTS test_history;
DROP TABLE IF EXISTS test_case_files;
DROP TABLE IF EXISTS test_case_param;
DROP TABLE IF EXISTS test_case;
DROP TABLE IF EXISTS report_hw;
DROP TABLE IF EXISTS report_voip;
DROP TABLE IF EXISTS report_unit;
DROP TABLE IF EXISTS report_group;
DROP TABLE IF EXISTS report_job;
DROP TABLE IF EXISTS report_syslog;
DROP TABLE IF EXISTS syslog;
DROP TABLE IF EXISTS script_execution;
DROP TABLE IF EXISTS monitor_event;
DROP TABLE IF EXISTS message;
DROP TABLE IF EXISTS certificate;
-- Tables with some foreign keys
DROP TABLE IF EXISTS trigger_event;
DROP TABLE IF EXISTS trigger_release;
DROP TABLE IF EXISTS trigger_;
DROP TABLE IF EXISTS heartbeat;
DROP TABLE IF EXISTS unit_job;
DROP TABLE IF EXISTS job_param;
DROP TABLE IF EXISTS job;
DROP TABLE IF EXISTS syslog_event;
DROP TABLE IF EXISTS filestore;
DROP TABLE IF EXISTS permission_;
DROP TABLE IF EXISTS user_;
DROP TABLE IF EXISTS group_param;
DROP TABLE IF EXISTS group_;
DROP TABLE IF EXISTS unit_param_session;
DROP TABLE IF EXISTS unit_param;
DROP TABLE IF EXISTS unit;
DROP TABLE IF EXISTS profile_param;
DROP TABLE IF EXISTS profile;
DROP TABLE IF EXISTS unit_type_param_value;
DROP TABLE IF EXISTS unit_type_param;
DROP TABLE IF EXISTS unit_type;


source tables/unit_type.sql;
source tables/unit_type_param.sql;
source tables/unit_type_param_value.sql;
source tables/profile.sql;
source tables/profile_param.sql;
source tables/unit.sql;
source tables/unit_param.sql;
source tables/unit_param_session.sql;
source tables/group_.sql;
source tables/group_param.sql;
source tables/user_.sql;
source tables/permission_.sql;
source tables/filestore.sql;
source tables/syslog_event.sql;
source tables/job.sql;
source tables/job_param.sql;
source tables/unit_job.sql;
source tables/heartbeat.sql;
source tables/trigger.sql;
source tables/trigger_event.sql;
source tables/trigger_release.sql;
-- Tables with no or few foreign keys
source tables/certificate.sql;
source tables/message.sql;
source tables/monitor_event.sql;
source tables/script_execution.sql;
source tables/syslog.sql;
source tables/report.sql;
source tables/test_case.sql;
source tables/test_case_param.sql;
source tables/test_case_files.sql;
source tables/test_history.sql;