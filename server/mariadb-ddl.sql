--create database mbox;

--CREATE USER 'mboxserver'@'localhost' IDENTIFIED BY 'catfishbookwormzebra';
--GRANT ALL PRIVILEGES ON mbox.* TO 'mboxserver'@'localhost';

drop database mbox;
create database mbox;
use mbox;

-- truncate table user;
-- drop table user;

CREATE TABLE user (
nickname varchar(40) not null,
userid char(23) not null ,

CONSTRAINT unique_nickname UNIQUE (nickname),
CONSTRAINT unique_userid UNIQUE (userid)
);

insert into user values ('stuart','bahoj-sibof-lobut-sujar');

-- truncate table app;
-- drop table app;

create table app (
appname varchar(20) not null,
appid tinyint unsigned not null , -- 0-255

CONSTRAINT unique_appname UNIQUE (appname)
);

insert into app values ('nxtmail',1);


-- truncate table app_user;
-- drop table app_user;

create table app_user (
appid tinyint unsigned not null , -- 0-255
userid varchar(23) not null,

CONSTRAINT unique_fields UNIQUE (appid, userid)
);

--insert into app_user values (1,'bahoj-sibof-lobut-sujar');


create table message (
messageId int unsigned auto_increment, -- 0-4294967295
appId tinyint unsigned not null,                -- 0-255
authorUserId varchar(23) not null,
targetUserId varchar(23) not null,
message varchar(255) not null,
unixtime_ms bigint unsigned not null,           -- 0-18446744073709551615
primary key(messageId)                          -- --now:1587202163242
);

create table pool (
poolId smallint unsigned auto_increment, -- 0-65535 (2 bytes)
appId tinyint unsigned not null,
size tinyint unsigned not null,
filled boolean not null,
created_unixtime_ms bigint unsigned not null,
updated_unixtime_ms bigint unsigned not null,
primary key(poolId)
);

create table user_in_pool (
poolId int unsigned not null, -- FK into pool?
userId varchar(23) not null   -- FK into user?
);