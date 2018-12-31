/*
In all scripts balance ease/time of creation, speed, and maintenance/readability.
*/

---------------------------------------------------------Part 1--------------------------------------------------------
/*
The following query is not returning all records correctly. Explain why and correct.
*/
---------------------------------------------------------
/*
Reason: comparing d.val raw in the where clause is faulty because it can be null due to the left join.
*/
select a.a_id, a.b_id, a.c_id, a.val, b.val, c.val, isnull(d.val,0) [val]
from table_a a
join table_b b on a.b_id = b.b_id
join table_c c on a.c_id = c.c_id
left join table_d d on c.d_id = d.d_id
where a.val >= 50
and b.val between 0 and 50
and isnull(d.val,0) <= 100

---------------------------------------------------------Part 2--------------------------------------------------------
/*
Given the following description create a script to setup the database. No data is needed just use best practices when creating these tables and model.

Homes are defined as the combination of address, address line two, state, and zip.
Homes can be apartments, free standing, town homes, condominiums, etc. This might not be known when the record is created.
States should be verified against the zip code.
Persons are defined as a driver's license or social security number.
Persons can have zero, one, or multiple homes. However, only one home can be the primary residence for the person.
Persons can be married to other persons.
*/
---------------------------------------------------------
/*
NOTE though it's more important to me to follow good locally established standards,
	I have a personal preference for creating databases with case-sensitive
	collation when appropriate (some companies I've worked with set case-sensitive
	collation at the server level), for example;
--create database APG collate Latin1_General_CS_AI
--select collation_name from sys.databases where name = 'APG'
--select serverproperty('collation')
*/
/*
declare @sql nvarchar(max) = ''

select @sql += 'drop trigger ' + quotename(s.name) + '.' + quotename(o.name) + ';' + char(10)
from sys.objects o
join sys.schemas s on o.schema_id = s.schema_id
where o.type = 'TR'
and s.name in ('dbo')
order by s.name, o.name

select @sql += 'alter table ' + quotename(s.name) + '.' + quotename(t.name)
	+ ' drop constraint ' + quotename(o.name) + ';' + char(10)
from sys.objects o
join sys.tables t on o.parent_object_id = t.object_id
join sys.schemas s on t.schema_id = s.schema_id
where o.type = 'F'
and s.name in ('dbo')
order by s.name, t.name, o.name

select @sql += 'drop table ' + quotename(s.name) + '.' + quotename(t.name) + ';' + char(10)
from sys.tables t
join sys.schemas s on t.schema_id = s.schema_id
where t.type = 'U'
and s.name in ('dbo')
order by s.name, t.name

exec sp_executesql @sql
*/
/*
NOTE script is idempotent, thus rerunnable even in production
NOTE though I'd usually create the tables in alphabetical order and
	defer foreign key creation until after all tables are created,
	I'm inlining foreign key constraints here for easier readability
*/
if object_id('dbo.State', 'U') is null
begin
	create table dbo.State (
		stateId int not null constraint PK_State primary key,
		stateCode char(2) not null constraint UK_State unique,
		stateName varchar(50) not null
	)
	insert dbo.State (stateId, stateCode, stateName)
	values (1, 'AA', 'Armed Forces Americas'),
		(2, 'AL', 'Alabama'),
		(3, 'AK', 'Alaska'),
		(4, 'AZ', 'Arizona'),
		-- ...
		(10, 'FL', 'Florida'),
		(26, 'MO', 'Missouri'),
		(38, 'OR', 'Oregon'),
		(44, 'TX', 'Texas')
		-- etc
end

if object_id('dbo.StateZip', 'U') is null
begin
	create table dbo.StateZip (
		stateZipId int identity(1,1) not null constraint PK_StateZip primary key nonclustered,
		stateId int not null constraint FK_StateZip_State references State,
		zip decimal(5,0) not null constraint CK_StateZip_zip check (zip > 500),
	-- cluster on the unique index
		constraint UK_StateZip unique clustered (stateId, zip)
	)
	insert dbo.StateZip (stateId, zip)
	values (1, 34038),
		(2, 35007),
		(3, 99502),
		(3, 99507),
		(4, 85003),
		(10, 33765),
		(10, 33755),
		(10, 33756),
		(26, 64111),
		(38, 97201),
		(38, 97378),
		(44, 73301)
		-- etc
end

if object_id('dbo.HomeType', 'U') is null
begin
	create table dbo.HomeType (
		homeTypeId int not null constraint PK_HomeType primary key,
		homeTypeName varchar(20) not null constraint UK_HomeType unique,
		active bit not null constraint DF_HomeType_active default 1
	)
	insert dbo.HomeType (homeTypeId, homeTypeName)
	values (1, 'apartment'),
		(2, 'condominium'),
		(3, 'town home'),
		(4, 'free standing')
		-- etc
end

if object_id('dbo.Home', 'U') is null
begin
	create table dbo.Home (
		homeId int identity(1,1) not null constraint PK_Home primary key,
		addressLine1 nvarchar(255) not null,
		addressLine2 nvarchar(255) not null,
		stateId int not null,
		zip decimal(5,0) not null,
		homeTypeId int constraint FK_Home_HomeType references HomeType,
		constraint FK_Home_StateZip foreign key (stateId, zip) references StateZip (stateId, zip)
	)
end
-- add indexes as needed to support most frequent queries, after initial data population/migration
-- for example:
if not exists (select 1 from sys.indexes where name = 'IX_Home_StateZip')
	create index IX_Home_StateZip on dbo.Home (stateId, zip) include (addressLine1)

if object_id('dbo.Person', 'U') is null
begin
	create table dbo.Person (
		personId int identity(1,1) not null constraint PK_Person primary key,
		ssn decimal(9,0),
		driversLicenseNumber varchar(20),
		driversLicenseStateId int constraint FK_Person_State references State,
		constraint CK_Person_ssn_or_dl check (isnull(ssn,0) > 0 or isnull(driversLicenseNumber, '') > '' and driversLicenseStateId is not null)
	)
end
-- example of adding a column in an itempotent script
if col_length('dbo.Person', 'primaryResidenceHomeId') is null
	alter table dbo.Person add primaryResidenceHomeId int

if object_id('dbo.PersonHome', 'U') is null
begin
	create table dbo.PersonHome (
		personHomeId int identity(1,1) not null constraint PK_PersonHome primary key nonclustered,
		personId int not null constraint FK_PersonHome_Person references Person,
		homeId int not null constraint FK_PersonHome_Home references Home,
		beginTime datetime2(0) not null constraint DF_PersonHome_beginDate default getdate(),
		endTime datetime2(0) null,
		constraint UK_PersonHome unique clustered (personId, homeId)
	)
end
if object_id('dbo.FK_Person_PersonHome', 'F') is null
	alter table dbo.Person add constraint FK_Person_PersonHome
		foreign key (personId, primaryResidenceHomeId) references dbo.PersonHome (personId, homeId)

if object_id('dbo.RelationshipType', 'U') is null
begin
	create table dbo.RelationshipType (
		relationshipTypeId int not null constraint PK_RelationshipType primary key,
		relationshipTypeName varchar(20) not null constraint UK_RelationshipType unique,
		active bit not null constraint DF_RelationshipType_active default 1
	)
	insert dbo.RelationshipType (relationshipTypeId, relationshipTypeName)
	values (1, 'spouse')
		-- etc
end

if object_id('dbo.Relationship', 'U') is null
begin
	create table dbo.Relationship (
		relationshipId int identity(1,1) not null constraint PK_Relationship primary key,
		personId int not null constraint FK_Relationship_Person references Person,
		relatedPersonId int not null constraint FK_Relationship_Person2 references Person,
		relationshipTypeId int not null constraint FK_Relationship_RelationshipType references RelationshipType
			constraint DF_Relationship_relationshipTypeId default 1,
		beginDate date not null constraint DF_Relationship_beginDate default getdate(),
		endDate date null,
	--make this constraint reflexive using trigger defined below
		constraint UK_Relationship unique (personId, relatedPersonId, relationshipTypeId),
	--disallow a person from being related to themselves (though this could be valid for some relationships)
		constraint CK_Relationship_personId_relatedPersonId check (personId <> relatedPersonId)
	)
end

if object_id('dbo.Relationship_InsertUpdate', 'TR') is not null
	drop trigger dbo.Relationship_InsertUpdate
go
create trigger dbo.Relationship_InsertUpdate on dbo.Relationship
after insert, update
as
declare @oldRelationshipTypeId int = isnull((select relationshipTypeId from deleted), 0)
declare @newRelationshipTypeId int = (select relationshipTypeId from inserted)

if @oldRelationshipTypeId <> @newRelationshipTypeId
and exists (select 1
	from dbo.RelationshipType
	where relationshipTypeId = @newRelationshipTypeId
	and active = 0)
begin
	raiserror ('Specified RelationshipType is inactive.', 16, 1)
	rollback transaction
	return
end

if exists (select 1
	from dbo.Relationship r join inserted i
		on r.personId = i.relatedPersonId
		and r.relatedPersonId = i.personId
		and r.relationshipTypeId = i.relationshipTypeId)
begin
	raiserror ('Specified Relationship already exists reflexively.', 16, 1)
	rollback transaction
	return
end
go
/* TEST
insert Person(ssn) values (1), (2)
insert RelationshipType(relationshipTypeId, relationshipTypeName, active) values (2, 'Cousin', 0)
insert Relationship(personId, relatedPersonId) values (2, 1)
declare @relationshipId int = scope_identity()
update RelationshipType set active = 0 where relationshipTypeId = 2
update Relationship set relationshipTypeId = 2 where relationshipId = @relationshipId
*/

---------------------------------------------------------Part 3--------------------------------------------------------
create table [dbo].[sample_table](
	[id] [int] identity(1,1) not null,
	[date] [varchar](255) null,
	[hour1] [varchar](255) null,
	[hour2] [varchar](255) null,
	[hour3] [varchar](255) null,
	[hour4] [varchar](255) null,
	[hour5] [varchar](255) null,
	[hour6] [varchar](255) null,
	[hour7] [varchar](255) null,
	[hour8] [varchar](255) null,
	[hour9] [varchar](255) null,
	[hour10] [varchar](255) null,
	[hour11] [varchar](255) null,
	[hour12] [varchar](255) null,
	[hour13] [varchar](255) null,
	[hour14] [varchar](255) null,
	[hour15] [varchar](255) null,
	[hour16] [varchar](255) null,
	[hour17] [varchar](255) null,
	[hour18] [varchar](255) null,
	[hour19] [varchar](255) null,
	[hour20] [varchar](255) null,
	[hour21] [varchar](255) null,
	[hour22] [varchar](255) null,
	[hour23] [varchar](255) null,
	[hour24] [varchar](255) null)

insert into [dbo].[sample_table] ([date], [hour1], [hour2], [hour3], [hour4], [hour5], [hour6], [hour7], [hour8], [hour9], [hour10], [hour11], [hour12], [hour13], [hour14], [hour15], [hour16], [hour17], [hour18], [hour19], [hour20], [hour21], [hour22], [hour23], [hour24])
values 
('2015-05-25', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '-11', '12', '13', '14', '15', '16', '17', '18', '19', '20', '21', '22', null, '24'),
('2015-07-12', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10.5', '11', '12', '13', '14', '15', '16', '17', '18', '19', '20', '21', '22', '23', '24'),
('2016-11-01', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13', 'test', '15', '16', '17', '18', '19', '20', '21', '22', '23', '24'),
('2014-05-25', '1', '2', '3', '4', '5', '6', '7', '8.954', '9', '10', '11', '12', '13', '14', '15', '16', '17', '18', '19', '20', '21', '22', '23', '24')

/*
Given the above table write a script that returns the data in rows for id, datetime [new field], value [new field].

example:

id	full_date			value
1	2015-05-25 13:00:00	13
1	2015-05-25 14:00:00	14
2	2015-07-12 08:00:00	8
4	2014-05-25 08:00:00	8.954
*/
---------------------------------------------------------
select id
	, full_date = dateadd(hour, convert(int, substring(colname, 5, 2)), convert(datetime, [date]))
	, value
from sample_table
unpivot (
	value for colname in (hour1, hour2, hour3, hour4, hour5, hour6, hour7, hour8, hour9, hour10, hour11, hour12
			, hour13, hour14, hour15, hour16, hour17, hour18, hour19, hour20, hour21, hour22, hour23, hour24)
) u
order by id, full_date

---------------------------------------------------------Part 4--------------------------------------------------------
create table #load_table
(id int identity(1,1) not null,
a int not null,
b int not null,
c int not null,
val decimal(8,2) null,
primary key (a,b,c))

create table [dbo].[main]
(id int identity(1,1) not null constraint [PK_main] primary key,
a int not null,
b int not null,
c int not null,
val decimal(8,2) not null)

create unique nonclustered index [UX_abc] on [dbo].[main] (a, b, c)

insert into #load_table (a, b, c, val)
values
(1, 1, 1, 3.62),
(4, 1, 1, null),
(1, 2, 1, 16.54),
(1, 1, 4, -9.25),
(1, 1, 2, null)

insert into [dbo].[main] (a, b, c, val)
values
(1, 1, 1, 3.67),
(2, 1, 1, 0),
(1, 2, 1, 48444.00),
(4, 1, 1, 5.00)

/*
The #load_table can contain completely new data as well as updated data (as compared to dbo.main).

Given the above tables create a stored procedure that can run either of the scripts below depending on parameter passed.
1) a single query that populates dbo.main from #load_table
2) a loop that populates dbo.main one record at a time, handles errors, and logs errors from #load_table and will continue to run until complete.

*/
---------------------------------------------------------
if object_id('tempdb..#load_error', 'U') is not null
	drop table #load_error
go
create table #load_error (
	a int not null,
	b int not null,
	c int not null,
	val decimal(8,2) null,
	msg nvarchar(max) not null
)
go

if object_id('dbo.main_load', 'P') is not null
	drop procedure dbo.main_load
go
create procedure dbo.main_load
	@ignoreErrors bit = 0
as
begin
	set nocount on

	truncate table #load_error

	if @ignoreErrors = 1
	begin
		merge dbo.main m
		using #load_table l on m.a = l.a and m.b = l.b and m.c = l.c
		when matched and l.val is null
			then delete
		when matched and l.val is not null
			then update set m.val = l.val
		when not matched by target and l.val is not null
			then insert (a, b, c, val)
				values (l.a, l.b, l.c, l.val);
		delete #load_table
		return
	end

	declare @id int,
		@a int, @b int, @c int,
		@val decimal(8,2)

	declare load_cursor cursor
	local forward_only static read_only
	for select id, a, b, c, val
		from #load_table

	open load_cursor
	fetch next from load_cursor
		into @id, @a, @b, @c, @val
	while @@fetch_status = 0
	begin
		begin try
			if @val is null
				delete dbo.main
					where a = @a and b = @b and c = @c
			else begin
				update dbo.main
					set val = @val
					where a = @a and b = @b and c = @c
				if @@rowcount = 0
					insert dbo.main (a, b, c, val)
						select @a, @b, @c, @val
			end
			delete #load_table where id = @id
		end try
		begin catch
			-- could save other error attributes here, just grabbing message for simplicity
			declare @msg nvarchar(max)
			select @msg = error_message()
			insert #load_error (a, b, c, val, msg)
				select @a, @b, @c, @val, @msg
			delete #load_table where id = @id
		end catch

		fetch next from load_cursor
			into @id, @a, @b, @c, @val
	end

	close load_cursor
	deallocate load_cursor
end
go

/* TEST
exec main_load
select * from #load_error
select * from #load_table
select * from dbo.main

insert into #load_table (a, b, c, val)
values
(1, 1, 1, 3.61),
(4, 1, 1, 1),
(1, 2, 1, 16.54),
(1, 1, 4, -9.25),
(2, 1, 1, null)
exec main_load 1
select * from #load_error
select * from #load_table
select * from dbo.main
*/

---------------------------------------------------------Part 5--------------------------------------------------------
create table [dbo].[test]
(id int identity(1,1) not null constraint [PK_test] primary key,
person_id int not null,
val decimal(8,2) null,
inserted_date datetime2(0) not null constraint [DF_test_inserted_date] default (getdate()))

insert into [dbo].[test] (person_id, val, inserted_date)
values
(1, null, '2015-12-01 11:00'),
(2, 213.12, '2015-12-01 14:00'),
(3, 21.12, '2015-12-01 15:00'),
(1, 13.12, '2015-12-01 15:00'),
(2, 23.12, '2015-12-01 10:00'),
(2, null, '2015-12-01 15:00')

/*
Given the above table create a script that returns the last (newest inserted_date) val for each person_id.
Only return rows with a non-null value. (person_id 2 should not be returned)
*/
---------------------------------------------------------
-- exists
select person_id, max(inserted_date)
from dbo.test t
where not exists (select 1 from dbo.test
	where person_id = t.person_id and val is null)
group by person_id

-- in
select person_id, max(inserted_date)
from dbo.test
where person_id not in (
	select person_id from dbo.test where val is null)
group by person_id

-- subquery
select t.person_id, max(t.inserted_date)
from dbo.test t
left join (
	select distinct person_id from dbo.test where val is null
) anynull on t.person_id = anynull.person_id
where anynull.person_id is null
group by t.person_id

---------------------------------------------------------Part 6 Extra Credit--------------------------------------------------------
--Script(s) using CTE and prepared to discuss them during the call
------------------------------------------------------------------------------------------------------------------------------------
-- simple recursive CTE for fun
;with nums(val) as (
	select 1
	union all
	select val + 1 from nums where val < 50
)
select val from nums

-- unique non-overlapping date segments
-- segments that start later take precedence; if two start on same date then earlier end takes precedence
;with example as (
	select * from (values
		(1, 'a', '2018-09-01', '2018-09-30'),
		(1, 'b', '2018-09-16', '2018-09-29'),
		(1, 'c', '2018-09-06', '2018-09-09'),
		(1, 'b', '2018-09-12', '2018-09-13'),
		(1, 'c', '2018-09-12', '2018-09-19'),
		(1, 'b', '2018-08-01', '2018-08-31'),
		(2, 'a', '2018-09-02', '2018-09-28')
	) x (person_id, service_code, begin_date, end_date)
), segments(id, person_id, service_code, begin_date, end_date) as (
	select row_number() over(order by person_id), person_id, service_code
		, convert(date, begin_date), convert(date, end_date)
	from example
), precedence as (
	select id, person_id, service_code, begin_date, end_date
		, row_num = row_number() over(partition by person_id order by begin_date, end_date desc, service_code)
	from segments
), overlap as (
	select s1.id, s1.person_id, s1.service_code, s1.begin_date, s1.end_date
		, next_begin_date = s2.begin_date, next_end_date = s2.end_date
		, row_num = row_number() over(partition by s1.id order by s2.row_num)
	from precedence s1
	left join precedence s2 on s1.person_id = s2.person_id and s1.row_num < s2.row_num
		and s1.begin_date <= s2.end_date and s2.begin_date <= s1.end_date
), chunk(id, person_id, service_code, begin_date, end_date, new_begin_date, new_end_date) as (
	-- first segment
	select id, person_id, service_code, begin_date, end_date
			, begin_date, isnull(dateadd(day, -1, next_begin_date), end_date)
		from overlap where row_num = 1
	union all -- middle segments
	select o1.id, o1.person_id, o1.service_code, o1.begin_date, o1.end_date
			, dateadd(day, 1, o2.next_end_date), dateadd(day, -1, o1.next_begin_date)
		from overlap o1 join overlap o2 on o1.id = o2.id and o1.row_num - 1 = o2.row_num
	union all -- trailing segment
	select id, person_id, service_code, begin_date, end_date
			, max(dateadd(day, 1, next_end_date)), end_date
		from overlap
		group by id, person_id, service_code, begin_date, end_date
), filtered as (
	select person_id, service_code, begin_date = new_begin_date, end_date = new_end_date
		, row_num = row_number() over(partition by person_id, new_begin_date, new_end_date order by begin_date desc, end_date)
	from chunk
	where new_begin_date <= new_end_date
)
select person_id, begin_date, end_date, service_code
from filtered
where row_num = 1
order by person_id, begin_date, end_date

