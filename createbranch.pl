


use File::Basename;
use File::Temp qw( tempfile tempdir) ;
use FileHandle;
use Text::ParseWords;
use POSIX qw( strftime ); 
use Cwd;
use Data::Dumper;
use Getopt::Long;
use LWP::UserAgent;
use HTTP::Request;
#use JSON qw( decode_json);


our %buildinfo;
our $relver;
our $securetag;
our $mwintegtag;
our $oldbuild="PTL_REL_DT";
our $newbuild;
our $branch;
our $pomversion;
our $securepomversion;
our $browser = LWP::UserAgent->new or die qq(Cannot get User Agent);
our $request = HTTP::Request->new;
our $jenkinsgetdata;
our $jenkinsid = "arokiarajj";
our $jenkinstoken = "9eff8d3b5bc43a1440576b5d44140bcc";
$request->authorization_basic("$jenkinsid", "$jenkinstoken");
#$buildinfo{"branchtime"} = strftime("%Y-%m-%d-%H_%M_%S", localtime).$_[0];

our $TMP_BASE = "/tmp/logs/createbranch/" . $buildinfo{"deploytime"} ;
my $REAL_LOG_FILE = "$TMP_BASE" . "createbranch" .  "-" . strftime("%Y-%m-%d-%H-%M",localtime).$_[0] . ".log";
my $LOG_FILE = new FileHandle;
## Can be overridden later by initializeLog()
initializeLog($REAL_LOG_FILE);
init();
logLine();
# Release Deployment Log Location
$buildinfo{"log"} = $REAL_LOG_FILE;
$newbuild = $branch;
$branch = "DSP" . "$branch";
our $jenkinsoldbuilduri = "http://jenkins.devsecure.dsp:8080/view/RelBuild/job/" . "ReleaseBuildGoldAuto_" . "$oldbuild";
our $jenkinsnewbuilduri = "http://jenkins.devsecure.dsp:8080/job/" . "ReleaseBuildGoldAuto_hash" . "$newbuild";
our $buildconfig = "/tmp/logs/createbranch/"  . "buildjob" . strftime("%Y-%m-%d-%H-%M",localtime).$_[0] . ".xml";
our $nexusconfig = "/tmp/logs/createbranch/"  . "nexusjob" . strftime("%Y-%m-%d-%H-%M",localtime).$_[0] . ".json";
our %scm = (
              "ie2-common-nonsecure"  => 'https://dsp.define.devsecure.dsp/svn/ie2-common-nonsecure/branches/ptl/support/' . "$branch" ,
              "ie2-app-secure" => 'https://dsp.define.devsecure.dsp/svn/ie2-app-secure/branches/ptl/support/' . "$branch" ,
              "ie2-app-motorway" => 'https://dsp.define.devsecure.dsp/svn/ie2-app-secure/modules/ie2-app-motorway/branches/ptl/support/' .  "$branch",
              "scmscripts" => 'https://dsp.define.devsecure.dsp/svn/ie2-common-nonsecure/modules/SCMScripts/trunk',
              "ie2-common-nonsecure-dtrain" => 'https://dsp.define.devsecure.dsp/svn/ie2-common-nonsecure/branches/ptl/REL',
              "ie2-app-secure-dtrain" => 'https://dsp.define.devsecure.dsp/svn/ie2-app-secure/branches/ptl/REL',
               "ie2-app-motorway-dtrain" => 'https://dsp.define.devsecure.dsp/svn/ie2-app-secure/modules/ie2-app-motorway/branches/ptl/REL',
               );

our $nexustemplate = <<'END_MESSAGE';
{
        data: {
        "id": "releases-vxxxx",
        "name": "releases-vxxxx",
        "exposed": true,
        "repoType": "hosted",
        "repoPolicy": "RELEASE",
        "providerRole": "org.sonatype.nexus.proxy.repository.Repository",
        "notFoundCacheTTL": 1440,
        "browseable": true,
        "indexable": true,
        "provider": "maven2",
        "format": "maven2"
        }
}
END_MESSAGE

our $relconfig =  <<'END_MESG';
elsif (lc $stream eq lc "ptl_RELNO")
{
  $cn_branch = "ptl/support/DSPRELNO";
  $as_branch = "ptl/support/DSPRELNO";
  $mb_branch = "ptl/support/DSPRELNO";
  $as_snapshot = "POMVER";
  $version_pre = "MAJORVER";
  $version_baseline = "BASEVER";    
  $gldrel = 1;
  # The JenkinsJob value to get from the DEV team
  $jenkinsJob = "xxxxx";
  $platform = "hash44";
  $refenv  = "xxxx";
}
END_MESG

# Checking the exitence of SVN branch, Nexus Repo and Jenkins Job
precheck();
#Create branch for all repos             
createbranch();

#Iterate thru all the repos
checkout("ie2-common-nonsecure");
getpomversion("ie2-common-nonsecure");
versionupdate("ie2-common-nonsecure");
commitchange("ie2-common-nonsecure");
checkout("ie2-app-secure");
getpomversion("ie2-app-secure");
versionupdate("ie2-app-secure");
commitchange("ie2-app-secure");
checkout("ie2-app-motorway");
getpomversion("ie2-app-motorway");
versionupdate("ie2-app-motorway");
commitchange("ie2-app-motorway");

#Creating Jenkins Release build job
getoldjobconfig();
createreleasejob();
# Create Nexus Repo
createnexusrepo();
#Update release build script
addtoreleasebuild();

#Updating to Dtrain POM
checkout_dtrain("ie2-common-nonsecure-dtrain");
checkout_dtrain("ie2-app-secure-dtrain");
checkout_dtrain("ie2-app-motorway-dtrain");
versionupdate_dtrain("ie2-common-nonsecure-dtrain");
versionupdate_dtrain("ie2-app-secure-dtrain");
versionupdate_dtrain("ie2-app-motorway-dtrain");

sub addtoreleasebuild {
 my $repo = shift;
 chomp $repo;
 chomp $securepomversion;
 my $searchrel = "ptl_"."$newbuild";
 my $lookup = "0";
 my $verchange = "  \$version_pre = " . "\"". $newnexusrepo . "\"" . ";\n";
 echoText("Checking Out scmscripts repo  \n");
 if ( -d "/home/$ENV{'LOGNAME'}/scmscripts" )  {
  tryCommand("rm -rf /home/$ENV{'LOGNAME'}/scmscripts");
 }
 tryCommand("cd /home/$ENV{'LOGNAME'} && mkdir -p scmscripts && cd  /home/$ENV{'LOGNAME'}/scmscripts ; /usr/bin/svn checkout  $scm{scmscripts}");
 my $out = ( system("grep $searchrel /home/$ENV{'LOGNAME'}/scmscripts/trunk/ReleaseBuild_WithMKS.pl >/dev/null") ) ? 0 : 1;
 if ($out eq "1") {
  exitWithError("Release Section already exists for $searchrel release in the release build script", 1); 
 }
 $securepomversion =~ m/^(\d+).*$/;
 my $majorver = $1;
 echoText("MajorVer: $majorver\n");
 $securepomversion =~ m/^\d+.\d+.(\d+).*$/;
 $securepomversion =  $securepomversion . "-SNAPSHOT";
 my $basever = $1;
 echoText("BaseVer: $basever\n");
 chomp $basever;
 chomp $majorver;
 $relconfig =~ s/RELNO/$newbuild/g;
 $relconfig =~ s/POMVER/$securepomversion/;
 $relconfig =~ s/MAJORVER/$majorver/;
 $relconfig =~ s/BASEVER/$basever/;
 echoText("Relconfig:$relconfig \n");
 open (my $wr, '+>', "/home/$ENV{'LOGNAME'}/scmscripts/trunk/ReleaseBuild_WithMKS_tmp.pl");
 open (my $re, '+<', "/home/$ENV{'LOGNAME'}/scmscripts/trunk/ReleaseBuild_WithMKS.pl");
  while (my $redata=<$re>) {
     chomp $redata;
     $redata = $redata . "\n";
      if ($redata =~ /\"ptl_rel\"/ ) {
       $lookup = "1";
     }
      if (($redata =~ /version_pre/) && ($lookup eq "1")){
        print $wr $verchange;
        $lookup = "0";
        next;
     }

     if ($redata =~ /#BRANCHSECTION/) {
        print $wr $relconfig;
        print $wr $redata;
     } else {
       print $wr $redata;
     }
 }
 close($wr);
 close($re);
tryCommand("cp /home/$ENV{'LOGNAME'}/scmscripts/trunk/ReleaseBuild_WithMKS_tmp.pl /home/$ENV{'LOGNAME'}/scmscripts/trunk/ReleaseBuild_WithMKS.pl");
tryCommand("rm /home/$ENV{'LOGNAME'}/scmscripts/trunk/ReleaseBuild_WithMKS_tmp.pl");
tryCommand("cd  /home/$ENV{'LOGNAME'}/scmscripts/trunk ; /usr/bin/svn commit  -m \" #60635 Release build script updated with new release version $newbuild \"");
echoText("Committed Release Build script  changes  succesfully \n");



}


sub getoldjobconfig {
  echoText("Going to extract oldrelease build job $oldbuild config\n");
  $request->method("GET");
  $request->url("$jenkinsoldbuilduri/config.xml");
  my $response = $browser->request($request);
  $jenkinsgetdata = $response->content;
  if ( not $response->is_success ) {
        die qq(Horribly wrong GET Simon...);
      }
  $jenkinsgetdata =~ s/ptl_rel/ptl_$newbuild/g;
  logText("Build Config for the new job:$jenkinsgetdata");
  open (my $wf, '+>', "$buildconfig");
  print $wf $jenkinsgetdata;
  close($wf);
}

sub createreleasejob {
 echoText("Going to create new Jenkins release build job\n");
 echoText("/usr/bin/curl -s -XPOST http://jenkins.devsecure.dsp:8080/createItem?name=ReleaseBuildGoldAuto_hash$newbuild -u $jenkinsid:$jenkinstoken --data-binary \@$buildconfig -H \"Content-Type:text/xml\"\n");
 tryCommand("/usr/bin/curl -s -XPOST http://jenkins.devsecure.dsp:8080/createItem?name=ReleaseBuildGoldAuto_hash$newbuild -u $jenkinsid:$jenkinstoken --data-binary \@$buildconfig  -H \"Content-Type:text/xml\"");
 echoText("Enabling new  release build job\n");
 tryCommand("/usr/bin/curl -s -XPOST http://jenkins.devsecure.dsp:8080/job/ReleaseBuildGoldAuto_hash$newbuild/enable -u $jenkinsid:$jenkinstoken");
 echoText("Created  and enabled new releasebuild job successfully\n");
}

#Creating Nexus Repo
sub createnexusrepo {
 $nexustemplate =~ s/xxxx/$newnexusrepo/g;
 echoText("Nexus Template after replacing the release ID: $nexustemplate \n");
 chomp $nexustemplate;
 open (my $nc, '+>', "$nexusconfig");
 print $nc $nexustemplate;
 close($nc);
 echoText("/usr/bin/curl -i -H \"Accept: application/json\" -H \"Content-Type: application/json\" -X POST  -v -trace-ascii -d \@$nexusconfig -u builder:xxxxxx http://nexus:8081/nexus/service/local/repositories \n");
 tryCommand("/usr/bin/curl -i -H \"Accept: application/json\" -H \"Content-Type: application/json\" -X POST  -v -trace-ascii  -d \@$nexusconfig -u builder:builder123 http://nexus:8081/nexus/service/local/repositories");
 echoText("Nexus Repo created successfully \n");
}

sub precheck {

 #Checking exitence of the support branch
 my $fail;
 `/usr/bin/svn info  https://dsp.define.devsecure.dsp/svn/ie2-common-nonsecure/branches/ptl/support/$branch`;
 if ($? eq "0") {
  echoText(" Common Nonsecure Support Branch $branch already exist. Please check the input parameters !!!\n");
  $fail = "1";
 }
  `/usr/bin/svn info  https://dsp.define.devsecure.dsp/svn/ie2-app-secure/branches/ptl/support/$branch`;
 if ($? eq "0") {
  echoText("AppSecure Support Branch $branch already exist. Please check the input parameters !!!\n");
  $fail = "1";
 }
 `/usr/bin/svn info  https://dsp.define.devsecure.dsp/svn/ie2-app-secure/modules/ie2-app-motorway/branches/ptl/support/$branch`;
 if ($? eq "0") {
  echoText("Motorway Intergaration Support Branch  $branch already exist. Please check the input parameters !!!\n");
  $fail = "1";
 }
 #Checking existence of the  Jenkins Job
 my @out = qx(/usr/bin/curl -XGET http://jenkins.devsecure.dsp:8080/checkJobName?value=ReleaseBuildGoldAuto_hash$newbuild -u $jenkinsid:$jenkinstoken);
 foreach my $line (@out) {
  if ($line =~ m/exist/) {
   echoText("Jenkins Job ReleaseBuildGoldAuto_hash$newbuild already exist. Please check the input parameters !!!\n");
   $fail = "1";
  }
 }
#Checking existence of the nexus repo
my @nexusout = qx(/usr/bin/curl  http://nexus:8081/nexus/service/local/repositories);
 foreach my $nexline (@nexusout) {
  if ($nexline =~ m/releases-v$newnexusrepo/) {
    echoText("Nexus Repo releases-v$newnexusrepo already exist. Please check the input parameters !!!\n");
    $fail = "1";
    last;
  }
 }

 if ($fail == "1") {
 exitWithError("Precheck Failed !!! Please investigate \n", 1);
 }

}


sub createbranch {
 echoText("Creating branch for ie2-common-nonsecure - RelTag: $securetag - NewBranch: $branch \n");
 tryCommand("/usr/bin/svn  copy https://dsp.define.devsecure.dsp/svn/ie2-common-nonsecure/reltags/ptl/REL/$securetag/   https://dsp.define.devsecure.dsp/svn/ie2-common-nonsecure/branches/ptl/support/$branch -m \" #64526 Create new branch $branch from releasetag $securetag - ie2-common-nonsecure \"");
 echoText("Created ie2-common-nonsecure  $branch successfully \n");
 echoText("Creating branch for ie2-app-secure - RelTag: $securetag - NewBranch: $branch \n");
 tryCommand("/usr/bin/svn  copy https://dsp.define.devsecure.dsp/svn/ie2-app-secure/reltags/ptl/REL/$securetag/   https://dsp.define.devsecure.dsp/svn/ie2-app-secure/branches/ptl/support/$branch -m \" #64526 Create new branch $branch from the releasetag $securetag  - ie2-app-secure\"");
 echoText("Created  ie2-app-secure  $branch successfully \n");
 echoText("Creating branch for ie2-app-motorway - RelTag: $mwintegtag - NewBranch: $branch \n");
 tryCommand("/usr/bin/svn  copy https://dsp.define.devsecure.dsp/svn/ie2-app-secure/modules/ie2-app-motorway/reltags/ptl/REL/$mwintegtag/   https://dsp.define.devsecure.dsp/svn/ie2-app-secure/modules/ie2-app-motorway/branches/ptl/support/$branch -m \" #64526 Create new branch $branch  from the releasetag $mwintegtag - ie2-app-motorway\"");
 echoText("Created ie2-app-motorway  $branch successfully \n");
}

sub checkout {
 my $repo = shift;
 chomp $repo;
 echoText("Checking Out $repo  - $scm{$repo} \n");
 if (( -d "/home/$ENV{'LOGNAME'}/$repo" ) && ($repo ne "")) { 
 tryCommand("rm -rf /home/$ENV{'LOGNAME'}/$repo");
 }
 tryCommand("cd /home/$ENV{'LOGNAME'} && mkdir -p $repo && cd  /home/$ENV{'LOGNAME'}/$repo ; /usr/bin/svn checkout  $scm{$repo}");
}


sub getpomversion {
  my $repo = shift;
  $pomversion = "";
  chomp $repo;
  logText("Pom File: $repo/$branch/pom.xml \n");
  open (my $rf, '+<', "/home/$ENV{'LOGNAME'}/$repo/$branch/pom.xml");
  while (my $rfdata=<$rf>) {
    chomp $rfdata;
    logText("Line:$rfdata\n");
    if ($rfdata =~ m/<version>(.+)<\/version>/){
     $pomversion = $1;
     if ($repo eq "ie2-app-secure") {
      $securepomversion = $pomversion;
     }
     last;
    } 
  }
   echoText("Current Pomversion -  $pomversion Repo: $repo \n");
}

sub versionupdate {
  my $repo = shift;
  chomp $repo;
  echoText("Going to make Version Update $repo  - $scm{$repo} in the pom files \n");
  tryCommand("cd  /home/$ENV{'LOGNAME'}/$repo/$branch ;  /bin/find . -type f -name \"pom.xml\" \| /usr/bin/xargs /usr/bin/perl -pi -e 's/version>$pomversion/version>$pomversion.0-SNAPSHOT/g' ");
  if ($repo eq "ie2-app-motorway") {
    tryCommand("cd  /home/$ENV{'LOGNAME'}/$repo/$branch ;  /bin/find . -type f -name \"pom.xml\" \| /usr/bin/xargs /usr/bin/perl -pi -e 's/version>$securepomversion/version>$securepomversion.0-SNAPSHOT/g' ");
  }
  echoText("Version Update $repo  - $scm{$repo} completed successfuly \n");
  tryCommand("cd  /home/$ENV{'LOGNAME'}/$repo/$branch && echo Modified Files && /usr/bin/svn status -u");
}

sub commitchange {
 my $repo = shift;
 chomp $repo;
 echoText("Going to commit  $repo  - $scm{$repo}  pom file changes \n");
 tryCommand("cd  /home/$ENV{'LOGNAME'}/$repo/$branch ; /usr/bin/svn commit  -m \" #64526 pomfile snapshot version update on $repo - $branch \"");
 echoText("Committed pom changes  in the repo:$repo - $scm{$repo}  succesfully \n");
}

sub checkout_dtrain {
 my $repo = shift;
 chomp $repo;
 echoText("Checking Out $repo  - $scm{$repo} \n");
 if (( -d "/home/$ENV{'LOGNAME'}/$repo" ) && ($repo ne "")) {
 tryCommand("rm -rf /home/$ENV{'LOGNAME'}/$repo");
 }
 tryCommand("cd /home/$ENV{'LOGNAME'} && mkdir -p $repo && cd  /home/$ENV{'LOGNAME'}/$repo ; /usr/bin/svn checkout  $scm{$repo} --depth empty");
 tryCommand("cd /home/$ENV{'LOGNAME'} && mkdir -p $repo && cd  /home/$ENV{'LOGNAME'}/$repo/REL ; /usr/bin/svn up pom.xml");
}

sub versionupdate_dtrain {
  my $repo = shift;
  chomp $repo;
  echoText("Going to make New Nexus Repo Update $repo  - $scm{$repo}  - REL Branch in the pom files \n");
  tryCommand("cd  /home/$ENV{'LOGNAME'}/$repo/REL ;  /bin/find . -type f -name \"pom.xml\" \| /usr/bin/xargs /usr/bin/perl -pi -e 's/releases-v\\d+/releases-v$newnexusrepo/g' ");
  tryCommand("cd  /home/$ENV{'LOGNAME'}/$repo/REL ;  /usr/bin/svn commit  -m \" #64526 pomfile nexus version update on $repo - REL Branch \"");
  echoText("New Nexus Repo Update to POM  $repo  - $scm{$repo} completed successfuly \n");
}





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
  echoText("[ERROR] $errmsg\n");
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


sub echoTextOnly
{
  print STDOUT $_[0];
  logText ($_[0]);
}

sub usage {
	echoLine();
	echoText("USAGE: createbranch.pl  -appsecure  <svn appsecure tag>  -mwinteg < svn mwinteg tag> -newbranch <svn new branch name>  -newnexusrepono <New Nexus repo No>\n");

	echoLine();
        exitWithError("The input given to this script is incorrect . Please check !!!", 1)
}

sub init {
     
   my $rc = GetOptions(
      "appsecure=s" => \$securetag,
      "mwinteg=s" => \$mwintegtag,
      "newbranchno=s" => \$branch,
      #"oldbuildno=s" => \$oldbuild,
      #"newbuildno=s" => \$newbuild,
      "newnexusrepono=s"  => \$newnexusrepo, 
   );
  
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
     # echoText("AAAADD\n");
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
    logText("Attempting to execute \`$tc_string\` in ".getcwd()."... ");
  }
  else{ logText("Attempting to execute \`$tc_string\` in ".getcwd()."... "); };
  my $pid = open(OP, $tc_string." 2>&1 |");
  #print "TC String $tc_string - PID $pid - Timeout $timeout \n"; 
  if($pid)
  {
     # print "KK \n";
    eval
    {
     # print "TT \n";
      $SIG{ALRM} = sub { print "\n"; echoText("Timed Out - Killing [$pid] (ran longer than ".$timeout." seconds)... ");
       if ($tc_interrupt_function)
       {
        #print "INT - $tc_interrupt_function\n";
        eval "$tc_interrupt_function()";
       # print "JJ \n";
       }
        #print "ZZ \n";
      };
      alarm $timeout;
    };
  }
 # print "GG \n";
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
   # print "DD\n";
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
   # print "EE \n";
    if(!$quiet || $quiet < 2)
    {
      echoTextOnly("[DONE]\n");
    }
    else{ logText("[DONE]\n"); }
    return 0;
  }
}
