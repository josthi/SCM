#!/usr/bin/perl
##############################################################################################################################################
## Component Version Update
##Description: This is used to perform voltdb  and oracle row count 
## *** Author Joseph Simon Arokiaraj
## Date: 02-10-17
###############################################################################################################################################


use File::Basename;
use File::Temp qw( tempfile tempdir) ;
use FileHandle;
use Text::ParseWords;
use POSIX qw( strftime ); 
use Cwd;
use Data::Dumper;
use Getopt::Long;
use DBI;


our $env;
our $envno;
#our $dbuser="app_user";
#our $pass="Pa55w0rd";
#our $host="10.110.65.24";
#our $db="dsp_portal";
our @count;
our $env_id;
our $rel_id;
our %rmvolt;
our %cspvolt;
our %oracle;
our $df_id;
our $jobstatus;
our $jobname = "oraclevoltrowcount";
#our $dbh = DBI->connect("DBI:mysql:$db:$host", $dbuser, $pass);
our $timestamp = strftime("%Y-%m-%d %H:%M:%S",localtime).$_[0];
our $dberror = 0;
our $oracledberror = 0;
our %relversion = ("systest1"=>"1.4",
             "systest2"=>"2.1",
             "systest3"=>"1.4",
             "systest4"=>"2.1",
             "systest5"=>"2.1",
             "systest6"=>"1.4",
             "sit2"=>"2.1",
             "uit1"=>"1.3.1",
             "dev3"=>"2.1",
             "dev4"=>"2.1",
             "dev5"=>"1.4",
             "dev6"=>"2.1");

our %attr = (RaiseError=>1,
           AutoCommit=>0);
#our $pdbh = DBI->connect("DBI:mysql:$db:$host", $dbuser, $pass,\%attr);
our $cnf = "$ENV{HOME}/db_cnf";
our $dsn = "DBI:mysql:;" . "mysql_read_default_file=$cnf" . ";mysql_read_default_group=dspportal";
our $dbh = DBI->connect(
    $dsn,
    undef,
    undef,
   {RaiseError => 1}
) or  die "DBI::errstr: $DBI::errstr";

our $pdbh = DBI->connect(
    $dsn,
    undef,
    undef,
    \%attr,
) or  die "DBI::errstr: $DBI::errstr";


#Initializing Log File
my $TMP_BASE = "/tmp";
my $REAL_LOG_FILE = "$TMP_BASE" . "/datafetch".  "-" . strftime("%Y-%m-%d-%H-%M",localtime).$_[0] . ".log";
my $LOG_FILE = new FileHandle;
## Can be overridden later by initializeLog()
initializeLog($REAL_LOG_FILE);

init();
logLine();
$jobstatus = getjobstatus();
if ($jobstatus ne "active") {
  exitWithError("Job $jobname state isn't active. Not going to progress. Terminating now !!!", 1);

}
$env_id = getenvid();
$rel_id = getrelid();
logText("Environment ID: $env_id\n");
logText("Release ID: $rel_id\n");
getrowcount();
populatesummary();
$df_id = getlastdfid();
logText("DF ID:$df_id\n");
$rmvolt{'df_id'} = $df_id;
$cspvolt{'df_id'} = $df_id;
populatermvoltrowcount();
populatecspvoltrowcount();
update_jobstatus();
getoraclecount();
populateoraclecount();
update_oracle_jobstatus();

exit 0;


#####################################################################################

#Fetching environment ID
sub getenvid {
logText("Entering getenvid method \n");
#my $dbh = DBI->connect("DBI:mysql:$db:$host", $dbuser, $pass);
my @row;
my ($query,@res) = "select e_id from environment where name = '$env' ";
$sqlQuery  = $dbh->prepare($query) or die "Can't prepare $query: $dbh->errstr\n";
$sqlQuery->execute(@res) or die "can't execute the query: $sqlQuery->errstr";

while (@row= $sqlQuery->fetchrow_array()) {
logText("Environment ID: $row[0]\n");last;
}
return $row[0];
}
#####################################################################################
#Checking  job state
sub getjobstatus {
logText("Entering getjobstatus  method \n");
my @row;
my ($query,@res) = "select state from job where name = '$jobname' ";
$sqlQuery  = $dbh->prepare($query) or die "Can't prepare $query: $dbh->errstr\n";
$sqlQuery->execute(@res) or die "can't execute the query: $sqlQuery->errstr";

 while (@row= $sqlQuery->fetchrow_array()) {
    logText("Job State for job $jobname - $row[0]\n");last;
  }
return $row[0];
}
######################################################################################

#Fetching release ID
sub getrelid {
logText("Entering getrelid method \n");
my @row;
my ($query,@res) = "select rv_id from release_version where release_version = '$relversion{$env}' ";
$sqlQuery  = $dbh->prepare($query) or die "Can't prepare $query: $dbh->errstr\n";
$sqlQuery->execute(@res) or die "can't execute the query: $sqlQuery->errstr";

while (@row= $sqlQuery->fetchrow_array()) {
logText("Rel ID: $row[0]\n");last;
}
return $row[0];
}
#######################################################################################

sub populatesummary {
my $stmt = 'INSERT INTO data_fetch_summary (rv_id,e_id,run_datetime,last_updated,last_updated_by) VALUES (' .  "'" . $rel_id . "'"  . "," . "'" . $env_id . "'" .   "," . "'" . $timestamp . "'" .  "," . "'" . $timestamp . "'" . "," .  '1' . ");";
logText("Data Fetch Summary insert command $stmt \n");
$sqlQuery  = $dbh->prepare($stmt) or die "Can't prepare $query: $dbh->errstr\n";
$sqlQuery->execute or die "can't execute the query: $sqlQuery->errstr";
}

sub getlastdfid {
my $stmt = "SELECT df_id from data_fetch_summary ORDER BY df_id DESC  LIMIT 1";
logText("GetLast Data FetchID command $stmt \n");
$sqlQuery  = $dbh->prepare($stmt) or die "Can't prepare $query: $dbh->errstr\n";
$sqlQuery->execute or die "can't execute the query: $sqlQuery->errstr";
while (@row= $sqlQuery->fetchrow_array()) {
logText("Data Fetch  Summary ID: $row[0]\n");last;
}
return $row[0];
}


sub getrowcount {
 my @output;
 my $volt = "rmvolt";
 @output = qx( source /home/$ENV{USER}/ansi/ENV; cd $ENV{HOME}/ansi; cones $env 15; ansible-playbook -i releases/inv/$env plays/voltdb_row_count.yml );
 #if ($env =~ /uit1/) {
 #my @output = qx( source /home/arokiarajj/ansi/ENV; cd $ENV{HOME}/ansi; cones $env 15; ansible-playbook -i old-inv/$env plays/voltdb_row_count.yml );
 #} else {
 #  @output = qx( source /home/arokiarajj/ansi/ENV; cd $ENV{HOME}/ansi; cones $env 15; ansible-playbook -i releases/inv/$env plays/voltdb_row_count.yml );
 #}
 foreach my $line (@output) {
   
   logText("Line:$line \n");
   if ($line =~ /CSP_GATEWAY_STORE/)  {
      $volt = "cspvolt";
      my @count = split("=",$line);
      if ($#count  eq "1") { 
      $count[0] =~ s/^\s+|\s+|\W+$//g ;
      $count[0] =~ s/"//g;
      $count[1] =~ s/^\s+|\s+|\W+$//g ;
      $cspvolt{$count[0]} = $count[1];
      }
   }
   if ( $line !~ /=>/) {
      my @count = split("=",$line);
      if ($#count  eq "1") {
      $count[0] =~ s/"//g;
      $count[0] =~ s/^\s+|\s+|\W+$//g ;
      $count[1] =~ s/^\s+|\s+|\W+$//g ;
      $$volt{$count[0]} = $count[1];
     }
   }
 }
$rmvolt{'last_updated'} = $timestamp;
$rmvolt{'last_updated_by'} = '1';
$cspvolt{'last_updated'} = $timestamp;
$cspvolt{'last_updated_by'} = '1';

print Dumper(\%rmvolt);
print Dumper(\%cspvolt);
}

sub getoraclecount {
 my @output = qx( source /home/$ENV{USER}/ansi/ENV; cd $ENV{HOME}/ansi; cones $env 15; ansible-playbook -i releases/inv/$env plays/db_data_fetch.yml );
 foreach my $line (@output) {
   logText("Oracle Line:$line \n");
   if ($line =~ /MRC=/) {
    my @countinfo = split(/\\n/,$line);
    logText("Count Info:@countinfo\n");
    foreach(@countinfo) {
      logText("T:$_\n");
      if ($_ =~ /=/) {
         my @count = split(/=/,$_);
         logText("Actual Count $count[0] -  $count[1]\n");
         $oracle{$count[0]} = $count[1];
      }
     }
   }
 }
print Dumper(\%oracle);
}

sub populateoraclecount {
     echoText("Running the MySQL DB update task to populate Oracle Count Table ... \n");
     eval {
     my $stmt = 'INSERT INTO oracle_count (df_id,METER_REGISTRATION_CACHE,METER_INVENTORY_CACHE,last_updated,last_updated_by) VALUES ( ' . "'" . $df_id . "'" . "," . "'" . $oracle{'MRC'} . "'" . "," . "'" . $oracle{'MIC'}  . "'" . "," . "'" .  $timestamp . "'" . "," .  "'"  . '1' . "'" . ");";
    logText("Oracle Count insert statement $stmt \n");
    my $sqlquery = $pdbh->prepare($stmt) or die "Can't prepare $query: $pdbh->errstr\n";
    $sqlquery->execute or die "can't execute the query: $sqlquery->errstr";
    };

    if ($@) {
    logText("Error while populating RM row count  : $@");
    $pdbh->rollback();
    $oracledberror = 1;
  }
    $pdbh->commit();
    $pdbh->disconnect();
  }

sub update_oracle_jobstatus {

my $stmt;
if ($oracledberror eq "1") {
 $stmt = "UPDATE data_fetch_summary set oracle_status = \'FAILED\'  where df_id = \'$df_id\' ";
}else {
 $stmt = "UPDATE data_fetch_summary  set oracle_status = \'PASSED\'  where df_id = \'$df_id\' ";
}
logText("Update data_fetch_summary  table - $stmt\n");
$sqlQuery  = $dbh->prepare($stmt) or die "Can't prepare $query: $dbh->errstr\n";
$sqlQuery->execute or die "can't execute the query: $sqlQuery->errstr";

}





sub populatermvoltrowcount {
eval {
        my $stmt = 'INSERT INTO rmvolt_count (' . join(',', keys %rmvolt) . ') VALUES (' . join(',', ('?') x keys %rmvolt) . ')';
        $pdbh->do( $stmt, \%rmvolt , values %rmvolt);
    
  };
  if ($@) {
    logText("Error while populating RM row count  : $@");
    $pdbh->rollback();
    $dberror = 1;
  }
 $pdbh->commit();
# $pdbh->disconnect();
 }

sub populatecspvoltrowcount {
eval {
        my $stmt = 'INSERT INTO cspvolt_count (' . join(',', keys %cspvolt) . ') VALUES (' . join(',', ('?') x keys %cspvolt) . ')';
        $pdbh->do( $stmt, \%cspvolt , values %cspvolt);

  };
  if ($@) {
    logText("Error while populating CSP row count  : $@");
    $pdbh->rollback();
    $dberror = 1;
  }
 $pdbh->commit();
 #$pdbh->disconnect();
 }

sub update_jobstatus {

my $stmt;
if ($dberror eq "1") {
 $stmt = "UPDATE data_fetch_summary set volt_status = \'FAILED\'  where df_id = \'$df_id\' ";
}else {
 $stmt = "UPDATE data_fetch_summary  set volt_status = \'PASSED\'  where df_id = \'$df_id\' ";
}
logText("Update data_fetch_summary  table - $stmt\n");
$sqlQuery  = $dbh->prepare($stmt) or die "Can't prepare $query: $dbh->errstr\n";
$sqlQuery->execute or die "can't execute the query: $sqlQuery->errstr";

}




exit 0;


sub initializeLog
{
  my $IL_LF = shift;
  my $mode = shift;
  if(!$mode)
  {
    $mode = ">"
  }
  $REAL_LOG_FILE = $IL_LF;
  open (hLF, $mode.$IL_LF) || exitWithError("Could not open $IL_LF for writing", 1);
  $LOG_FILE = \*hLF;
}

sub echoText
{
  print STDOUT "| ".$_[0];
  logText ($_[0]);
}



sub logText
{
  my $lt_str = strftime("[%H:%M:%S %Y-%m-%d] ", localtime).$_[0];
  my $written = syswrite $LOG_FILE, $lt_str, length($lt_str);
}

sub logTextOnly
{
  print STDOUT $_[0];
  logText ($_[0]);
}

sub echoLine
{
  my $l = "+-------------------------------------------------------------------------------\n";
  print STDOUT $l;
  logText($l);
}

sub logLine
{
  my $l = "+--------------------------------------------------------------------
-----------\n";
  logText($l);
}


sub exitWithError
{
  my ($errmsg, $errcode) = @_;
  logText("[ERROR] $errmsg\n");
  if(!exists &main::exitHandler)
  {
    logText("exitHandler function not found - exiting uncleanly...\n");
    #print STDERR "Fatal Error - Exiting script - see $REAL_LOG_FILE\n";
    exit $errcode;
  } else {
    logText("exitHandler function found - exiting cleanly...\n");
    #print STDERR "Fatal Error - Exiting script - see $REAL_LOG_FILE\n";
    return main::exitHandler($errcode);
  }
}

sub tryCommandiold
{

  my $tc_string = shift;
  my %extra = @_;
  my $tc_interrupt_function = $extra{interrupt};
  my $tc_log_file = $extra{log};
  my $tc_dir = $extra{dir};
  my $tc_verbose = $extra{verbose};
  my $noexit = $extra{noexit};
  my $tc_cwd = getcwd();
  my $tc_ret_code = 0;
  my $timeout = $extra{timeout};
  my $quiet = $extra{quiet};
  if(!$timeout)
  {

    $timeout = 10800;
  }

  if($tc_log_file)
  {
    open(LF, ">$tc_log_file") || exitWithError("Could not open $tc_log_file for writing", 1);
                syswrite LF, $tc_string."\n\n", length($tc_string) + 2;
  }
  if($tc_dir)
  {
    logText("Entering directory $tc_dir...\n");
    if(!chdir($tc_dir))
    {
      if($noexit)
      {
        logText("ERROR: Could not chdir to $tc_dir!!\n");
        return 1;
      }
      else
      {
        exitWithError("Could not chdir to $tc_dir!!\n", 1);
      }
    }
  }
  if(!$quiet)
  {
    logText("Attempting to execute \`$tc_string\` in ".getcwd()."... ");
  }
  else{ logText("Attempting to execute \`$tc_string\` in ".getcwd()."... "); };
  my $pid = open(OP, $tc_string." 2>&1 |");
  if($pid)
  {

    eval
    {
      $SIG{ALRM} = sub { print "\n"; logText("Timed Out - Killing [$pid] (ran longer than ".$timeout." seconds)... "); kill(9, $pid); };
      alarm $timeout;
    };
  }
   while (<OP>){
    if($tc_log_file)
    {
      syswrite LF, $_, length($_);
    }
    else
    {
      syswrite $LOG_FILE, strftime("[%H:%M:%S %Y-%m-%d] ", localtime).$_;
    }
     print $_;
    if($tc_verbose)
    {
      print $_;
    }
    if ($tc_interrupt_function)
    {
      eval "$tc_interrupt_function()";
    }
  }

  alarm 0;
  if($tc_dir)
  {
    logText("Leaving directory $tc_dir...\n");
    chdir($tc_cwd);
  }
  if($tc_log_file)
  {
    close(LF) || exitWithError("Could not close LF (".$tc_log_file.") file handle for some reason", 1);
  }
  if(!close(OP))
  {

    $tc_ret_code = $? >> 8;
    print "TTTTT:  $tc_ret_code \n";
  }
  if($tc_ret_code != 0)
  {
    print "DD\n";
    if(!$quiet || $quiet < 2)
    {
      echoTextOnly("[FAIL]\n");
    }
    else{ logText("[FAIL]\n"); }
    if(!$tc_log_file && !$noexit)
    {
      exitWithError("Command \"$tc_string\" returned error code $tc_ret_code\n", $tc_ret_code);
    }
     #This must have been killed, as the pipe is unhappy, yet the return code is 0,
     #realign the return code accordingly...
    if($tc_ret_code == 0)
    {
      $tc_ret_code = 1;
    }
    return $tc_ret_code;
  }
  else
  {
    print "EE \n";
     #Success - raise relevant return value
    if(!$quiet || $quiet < 2)
    {
      echoTextOnly("[DONE]\n");
    }
    else{ logText("[DONE]\n"); }
    return 0;
  }
}

sub echoTextOnly
{
  print STDOUT $_[0];
  logText ($_[0]);
}

sub usage {
	echoLine();
	echoText("USAGE: datafetch.pl  -env <envname> \n");
	echoLine();
	exit;
}

sub init {
     
   my $rc = GetOptions(
      "env=s" => \$env,
   );
   usage() if ( ! $env ) ;
  }



sub tryCommand
{
   my $tc_string = shift;
  my %extra = @_;
  my $tc_interrupt_function = $extra{interrupt};
  my $tc_log_file = $extra{log};
  my $tc_dir = $extra{dir};
  my $tc_verbose = $extra{verbose};
  my $noexit = $extra{noexit};
  my $tc_cwd = getcwd();
  my $tc_ret_code = 0;
  my $timeout = $extra{timeout};
  my $quiet = $extra{quiet};
  if(!$timeout)
  {
      echoText("AAAADD\n");
    $timeout = 18000;
  }
  if($tc_log_file)
  {
    open(LF, ">$tc_log_file") || exitWithError("Could not open $tc_log_file for writing", 1);
                syswrite LF, $tc_string."\n\n", length($tc_string) + 2;
  }
  if($tc_dir)
  {
    logText("Entering directory $tc_dir...\n");
    if(!chdir($tc_dir))
    {
      if($noexit)
      {
        echoText("ERROR: Could not chdir to $tc_dir!!\n");
        return 1;
      }
      else
      {
        exitWithError("Could not chdir to $tc_dir!!\n", 1);
      }
    }
  }
   if(!$quiet)
  {
    echoText("Attempting to execute \`$tc_string\` in ".getcwd()."... ");
  }
  else{ logText("Attempting to execute \`$tc_string\` in ".getcwd()."... "); };
  my $pid = open(OP, $tc_string." 2>&1 |");
  print "TC String $tc_string - PID $pid - Timeout $timeout \n"; 
  if($pid)
  {
      print "KK \n";
    eval
    {
      print "TT \n";
      $SIG{ALRM} = sub { print "\n"; echoText("Timed Out - Killing [$pid] (ran longer than ".$timeout." seconds)... ");
       if ($tc_interrupt_function)
       {
        print "INT - $tc_interrupt_function\n";
        eval "$tc_interrupt_function($pid)";
        print "JJ \n";
       }
        print "ZZ \n";
      };
      alarm $timeout;
    };
  }
  print "GG \n";
  while (<OP>){
    if($tc_log_file)
    {
      syswrite LF, $_, length($_);
    }
    else
    {
      syswrite $LOG_FILE, strftime("[%H:%M:%S %Y-%m-%d] ", localtime).$_;
    }
    if($tc_verbose)
    {
      print $_;
    }
   }
  alarm 0;
  if($tc_dir)
   {
    logText("Leaving directory $tc_dir...\n");
    chdir($tc_cwd);
  }
  if($tc_log_file)
  {
    close(LF) || exitWithError("Could not close LF (".$tc_log_file.") file handle for some reason", 1);
  }
  if(!close(OP))
  {
    $tc_ret_code = $? >> 8;
    print "TC:$tc_ret_code \n";
  }
  if($tc_ret_code != 0)
  {
    print "DD\n";
    if(!$quiet || $quiet < 2)
    {
      echoTextOnly("[FAIL]\n");
    }
    else{ logText("[FAIL]\n"); }
    if(!$tc_log_file && !$noexit)
    {
      exitWithError("Command \"$tc_string\" returned error code $tc_ret_code\n", $tc_ret_code);
    }
      if($tc_ret_code == 0)
    {
      $tc_ret_code = 1;
    }
    return $tc_ret_code;
  }
  else
  {
    print "EE \n";
    if(!$quiet || $quiet < 2)
    {
      echoTextOnly("[DONE]\n");
    }
    else{ logText("[DONE]\n"); }
    return 0;
  }
}
