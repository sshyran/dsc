package DSC::db;

use DBI;
use POSIX;

use strict;
use warnings;

BEGIN {
	use Exporter   ();
	use vars       qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
	$VERSION     = 1.00;
	@ISA	 = qw(Exporter);
	@EXPORT      = qw(
		&generic_init_db
		&specific_init_db
		&from_dummy
		&get_dbh
		&get_server_id
		&get_node_id
		&table_exists
		&create_data_table
		&create_data_indexes
		&data_table_names
		&data_index_names
	);
	%EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],
	@EXPORT_OK   = qw(
		$insert_suffix
		$key_type
	);
}
use vars      qw($datasource $username $password);
use vars      @EXPORT;
use vars      @EXPORT_OK;

END { }


# globals
$datasource = undef;
$username = undef;
$password = undef;
$insert_suffix = 'new';
$key_type = 'VARCHAR(1024)';

sub get_dbh {
    my %attrs = @_;
    my %defaults = (AutoCommit => 0);
    while (my ($key, $value) = each %defaults) {
	$attrs{$key} = $value if (!defined $attrs{$key});
    }
    # print STDERR "connecting to $datasource as $username\n";
    my $dbh = DBI->connect($datasource, $username, $password, \%attrs);
    if (!defined $dbh) {
	print STDERR "error connecting to database: $DBI::errstr\n";
	return undef;
    }
    my $drivername = $dbh->{Driver}->{Name};
    # print STDERR "driver name: $drivername\n";
    require "DSC/db/${drivername}.pm";
    return $dbh;
}

# non-driver-dependent db initialization
sub generic_init_db($) {
    my ($dbh) = @_;

    $dbh->do("CREATE TABLE server (" .
	"server_id   SMALLINT NOT NULL, " .
	"name        $key_type NOT NULL, " .
	"CONSTRAINT server_pkey PRIMARY KEY (server_id), " .
	"CONSTRAINT server_name_key UNIQUE (name))");

    $dbh->do("CREATE TABLE node (" .
	"node_id     SMALLINT NOT NULL, " .
	"server_id   SMALLINT NOT NULL, " .
	"name        $key_type NOT NULL, " .
	"CONSTRAINT node_pkey PRIMARY KEY (node_id), " .
	"CONSTRAINT node_server_id_fkey FOREIGN KEY (server_id) " .
	    "REFERENCES server (server_id), " .
	"CONSTRAINT node_name_key UNIQUE (server_id, name))");

    $dbh->do("CREATE TABLE loaded_files (" .
	"time        INTEGER NOT NULL, " .
	"dataset     $key_type NOT NULL, " .
	"server_id   SMALLINT NOT NULL, " .
	"node_id     SMALLINT NOT NULL)");
    $dbh->do("CREATE INDEX loaded_files_time ON loaded_files(time)");
};

# Find and execute the driver-specific or default implementation of the
# function.
sub dofunc {
    my $funcname = shift;
    my $dbh = shift || die "missing dbh parameter in $funcname";
    my $drvname = $dbh->{Driver}->{Name};
    my $func = $DSC::db::func->{$drvname}{$funcname};
    if (!defined $func) {
	$func = $DSC::db::default_func{$funcname};
	if (!defined $func) {
	    die "$funcname is not defined for driver $drvname\n";
	}
	$DSC::db::func{$drvname}{$funcname} = $func; # cache it
    }
    return &{$func}($dbh, @_);
}

sub specific_init_db    { dofunc('specific_init_db', @_); }
sub from_dummy          { dofunc('from_dummy', @_); }
sub get_server_id       { dofunc('get_server_id', @_); }
sub get_node_id         { dofunc('get_node_id', @_); }
sub table_exists        { dofunc('table_exists', @_); }
sub create_data_table   { dofunc('create_data_table', @_); }
sub create_data_indexes { dofunc('create_data_indexes', @_); }
sub data_table_names    { dofunc('data_table_names', @_); }
sub data_index_names    { dofunc('data_index_names', @_); }
sub read_data           { dofunc('read_data', @_); }
sub write_data          { dofunc('write_data', @_); }
sub write_data2         { dofunc('write_data2', @_); }
sub write_data3         { dofunc('write_data3', @_); }
sub write_data4         { dofunc('write_data4', @_); }

# $DSC::db::default_func contains default implementations of those
# operations that can be done portably.
# $DSC::db::func{$driver_name} contains driver-specific implementations.

%DSC::db::default_func = (

# Create db table(s) for a dataset.
# A dataset is split across two tables:
# ${tabname}_new contains the current day's data.  It is small and has few
#   indexes, so the once-per-minute inserts of new data are fast and the
#   plotter's queries aren't too slow.
# ${tabname}_old contains older data.  It is potentially very large, but has
#   more indexes needed to make the plotter's queries fast (the indexes are
#   created in a separate function).
# Old data is periodically moved from _new to _old.
# A view named ${tabname} is defined as the union of the _new and _old
# tables for querying convenience.  However, inserting/deleting/updating a
# view is not portable across database engines, so we will do those
# operations directly on the underlying tables.
#
create_data_table => sub {
    my ($dbh, $tabname, $dbkeys) = @_;

    print STDERR "creating table $tabname\n";
    my $def =
	"(" .
	"  server_id     SMALLINT NOT NULL, " .
	"  node_id       SMALLINT NOT NULL, " .
	"  start_time    INTEGER NOT NULL, " . # unix timestamp
	# "duration      INTEGER NOT NULL, " . # seconds
	(join '', map("$_ $key_type NOT NULL, ", grep(/^key/, @$dbkeys))) .
	"  count         INTEGER NOT NULL " .
	## Omitting primary key and foreign keys improves performance of inserts	## without any real negative impacts.
	# "CONSTRAINT $tabname_pkey PRIMARY KEY (server_id, node_id, start_time, key1), " .
	# "CONSTRAINT $tabname_server_id_fkey FOREIGN KEY (server_id) " .
	# "    REFERENCES server (server_id), " .
	# "CONSTRAINT $tabname_node_id_fkey FOREIGN KEY (node_id) " .
	# "    REFERENCES node (node_id), " .
	")";

    for my $sfx ('old', 'new') {
	my $sql = "CREATE TABLE ${tabname}_${sfx} $def";
	# print STDERR "SQL: $sql\n";
	$dbh->do($sql);
    }
    my $sql = "CREATE OR REPLACE VIEW $tabname AS " .
	"SELECT * FROM ${tabname}_old UNION ALL " .
	"SELECT * FROM ${tabname}_new";
    # print STDERR "SQL: $sql\n";
    $dbh->do($sql);
},

create_data_indexes => sub {
    my ($dbh, $tabname) = @_;
    $dbh->do("CREATE INDEX ${tabname}_new_time ON ${tabname}_new(start_time)");
    $dbh->do("CREATE INDEX ${tabname}_old_time_server_node ON ${tabname}_old(start_time, server_id, node_id)");
    $dbh->do("CREATE INDEX ${tabname}_old_server ON ${tabname}_old(server_id)");
    $dbh->do("CREATE INDEX ${tabname}_old_node ON ${tabname}_old(node_id)");
},

# Return a FROM clause for a dummy table (e.g., "FROM DUAL" in Oracle)
from_dummy => sub {
    "";
},

get_server_id => sub {
    my ($dbh, $server) = @_;
    my $server_id;
    my $sth = $dbh->prepare("SELECT server_id FROM server WHERE name = ?");
    $sth->execute($server);
    my @row = $sth->fetchrow_array;
    if (@row) {
	$server_id = $row[0];
    } else {
	$dbh->do('INSERT INTO server (name) VALUES(?)', undef, $server);
	$server_id = $dbh->last_insert_id(undef, undef, 'server', 'server_id');
    }
    return $server_id;
},

get_node_id => sub {
    my ($dbh, $server_id, $node) = @_;
    my $node_id;
    my $sth = $dbh->prepare(
	"SELECT node_id FROM node WHERE server_id = ? AND name = ?");
    $sth->execute($server_id, $node);
    my @row = $sth->fetchrow_array;
    if (@row) {
	$node_id = $row[0];
    } else {
	$dbh->do('INSERT INTO node (server_id, name) VALUES(?,?)',
	    undef, $server_id, $node);
	$node_id = $dbh->last_insert_id(undef, undef, 'node', 'node_id');
    }
    return $node_id;
},

#
# read from a db table into a hash
# TODO: if the requested time range does not overlap the ${tabname}_new table,
# we can omit that table from the query.
#
read_data => sub {
	my ($dbh, $href, $type, $server_id, $node_id, $start_time, $end_time,
	    $nogroup, $dbkeys, $where) = @_;
	my $nl = 0;
	my $tabname = "dsc_$type";
	my $sth;

	my $needgroup = !$nogroup ||
	    !defined $node_id && !(grep /^node_id/, @$dbkeys);
	my @params = ();
	my $sql = 'SELECT ' . join(', ', @$dbkeys);
	$sql .= $needgroup ? ', SUM(count) ' : ', count ';
	$sql .= "FROM $tabname WHERE ";
	if (defined $end_time) {
	    $sql .= 'start_time >= ? AND start_time < ? ';
	    push @params, $start_time, $end_time;
	} else {
	    $sql .= 'start_time = ? ';
	    push @params, $start_time;
	}
	$sql .= 'AND server_id = ? ';
	push @params, $server_id;
	if (defined $node_id) {
	    $sql .= 'AND node_id = ? ';
	    push @params, $node_id;
	}
	if ($where) {
	    $sql .= 'AND ' . $where . ' ';
	}
	$sql .= 'GROUP BY ' . join(', ', @$dbkeys) if ($needgroup);
	print STDERR "SQL: $sql;  PARAMS: ", join(', ', @params), "\n";
	$sth = $dbh->prepare($sql);
	$sth->execute(@params);

	while (my @row = $sth->fetchrow_array) {
	    $nl++;
	    if (scalar @$dbkeys == 1) {
		$href->{$row[0]} = $row[1];
	    } elsif (scalar @$dbkeys == 2) {
		$href->{$row[0]}{$row[1]} = $row[2];
	    } elsif (scalar @$dbkeys == 3) {
		$href->{$row[0]}{$row[1]}{$row[2]} = $row[3];
	    }
	}
	$dbh->commit;
	# print "read $nl rows from $tabname\n";
	return $nl;
}

);

1;
