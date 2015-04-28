#!/usr/bin/perl  
#
#
# This script call a REST api to get remote commands to execute
# It's part of provisioning script
# The direct ssh call is deprecated.
# Every command or script is stored in database and read from there
# 24.02.2014 A. cristalli
#
#
use Time::Piece;
use integer;
use POSIX qw(strftime);
use Backticks;
use Data::Dumper;
use Sys::Hostname;
use Socket;
use LWP::UserAgent;
use LWP::Simple;
use strict;
use warnings;
use integer;
use Switch;
use JSON ;
use feature qw(switch);
use HTTP::Cookies;
use HTTP::Request;
use LWP;
use File::Path qw{mkpath};
my @so;
my @rack;
my @shelf;
my @client;
my @client_ip;
my @args;
my @exeSeq;
my @scriptID;
my @retCode;
my @exeFlag;
my @logTime;
my @scriptName;
my @scriptContent;
my @remoteCommandID;
my @interpreter;
my @version;
my @execTime;
my @stdOut;
my @stdErr;
my $now_string = strftime "%H", gmtime;
my $file_path = "/tmp/";
my $f;
my @scheduled_time;
my $flag;
my $REST;
my $cmd;
my $ret = 0;
my $list;
sub getIPAddress() {
	my $ifconfig = `which ifconfig`
		or return "UNDEFINED1";
	chomp $ifconfig;
	my @ifconfig_output = `$ifconfig -a 2>&1`
		or return "UNDEFINED2";

	my $interface;
	my $STATE;
	my $IP;
	foreach  (@ifconfig_output) {
		$interface = $1 if /^(\S+?):?\s/;
		next unless defined $interface;
		$STATE = uc($1) if /\b(up|down)\b/i;
		$IP = $1 if /inet\D+(\d+\.\d+\.\d+\.\d+)/i;
		if ( defined $STATE and $STATE eq "UP" ) {
			if ( defined $IP and $IP ne "0.0.0.0" and $IP ne "127.0.0.1" ) {
				return $IP;
			}
		}
	}

	return "UNDEFINED3";
}

#first let know our ip address to before to call REST API

my $address = getIPAddress();
#
#
# Get data in json format, parse and prepare
# the argument is the client address to filter SQL request and the return values are all commands for client not yet executed
#

my $uri_get = 'http://'.$api_url.'/SPOT/provisioning/api/remotecommandses?';
my $uri_delete = 'http://'.$api_url.'/SPOT/provisioning/api/remotecommands/';
my $list_def = $uri_get.'clientaddress='.$address;
my $req_get= HTTP::Request->new( 'GET', $list_def);

#print $req_get->as_string();
my $get = LWP::UserAgent->new(
		requests_redirectable => [],
		timeout               => 10,
		);

my $datas = $get->request($req_get);
my $decoded = decode_json($datas->content);
my @recursive = @{ $decoded->{rows} };
if (scalar @recursive == 0) {
	print "\n REST interface: no remote commands found.\n";
}
my $uri_complete;
my $req_delete;
#print Dumper @recursive;
foreach  $f  ( @recursive ) {
	if ($f->{executionflag} ne 0 and $f->{executionflag} ne 100) {

		print "$f->{exectime}\n";
		my $nowTime = localtime;
		my $execTime = $f->{exectime};
		my $tp1 = Time::Piece->strptime($nowTime, '%a %b %d %H:%M:%S %Y');
		my $tp2 = Time::Piece->strptime($execTime, '%a %b %d %H:%M:%S %Y');
		print "Now is : $tp1 \n";
		my $diff = $tp1 - $tp2;
		print "Execution time of the script $tp2 \n";
		if ( $diff > 7200 ) {
			print "The difference is more than two hours\n";
			my $ua = LWP::UserAgent->new;
			$uri_complete = $uri_delete . $f->{remotecommandid};
			$req_delete = HTTP::Request->new( DELETE => $uri_complete);
			my $resp_delete = $ua->request($req_delete);
			print Dumper $resp_delete;
			print "\n REST interface: About to remove past successfull commands already executed....\n";
		}
		else
		{
			print "The difference is less than two hours.\nAborting delete from database.....\n";
		}
	}
	else
	{
		push(@so, $f->{salesorder});
		push(@rack, $f->{rack});
		push(@shelf, $f->{shelf});
		push(@client, "SO_".$f->{salesorder}."_rack".$f->{rack}."_shelf".$f->{shelf});
		push(@client_ip, $f->{clientaddress});
		push(@args, $f->{arguments});
		push(@exeSeq, $f->{exesequence});
		push(@scriptID, $f->{scriptid});
		push(@retCode, $f->{returncode});
		push(@stdOut, $f->{returnstdout});
		push(@stdErr, $f->{returnstderr});
		push(@exeFlag, $f->{executionflag});
		push(@logTime, $f->{logtime});
		push(@execTime, $f->{exectime});
# get script name and script content here
		my $uriGetScript = 'http://'.$api_url.'/SPOT/provisioning/api/provisioningscripts/'.$f->{scriptid};
		my $req_script_name = HTTP::Request->new( 'GET', $uriGetScript);
		
		my $scriptGet  = LWP::UserAgent->new(
				requests_redirectable => [],
				timeout               => 10,
				);
		my $Rawjson = $scriptGet->request($req_script_name);
		my $string = decode_json($Rawjson->content);
		my $Sname =  $string->{scriptname};
		my $Scontent = $string->{scriptcontent};
		my $Sinterpreter = $string->{interpreter};
		my $Sversion = $string->{version};
		push(@scriptName, $file_path.$f->{exesequence}."_SO_".$f->{salesorder}."_rack".$f->{rack}."_shelf".$f->{shelf}."_".$Sname);
		push(@scriptContent, $Scontent);
		push(@remoteCommandID, $f->{remotecommandid});
		push(@interpreter, $Sinterpreter);
		push(@version, $Sversion);
	}
}
#print Dumper @scriptID;

#print Dumper @scriptName;

#print Dumper @scriptContent;
# Here we are, all data got

# let's get the script associated

# Get the size of records

my $size = scalar @so;

# prepare the script to be executed in /tmp dir 


for (my $c = 0; $c < $size; $c++) {
	open my $fh, '>', $scriptName[$c];
	print $fh $scriptContent[$c];
	close($fh);
}
#print "Before sorting: \n";
#print Dumper @rack;
#print Dumper @shelf;
#print Dumper  @scriptName;
# Do a permutation on all arrays depending on execution sequence par client

my @permutation = sort { $exeSeq[$a] <=> $exeSeq[$b] } (0..$#exeSeq);

@so = @so[@permutation];
@rack = @rack[@permutation];
@shelf = @shelf[@permutation];
@client = @client[@permutation];
@client_ip = @client_ip[@permutation];
@args = @args[@permutation];
@exeSeq = @exeSeq[@permutation];
@scriptID = @scriptID[@permutation];
@retCode = @retCode[@permutation];
@exeFlag = @exeFlag[@permutation];
@logTime = @logTime[@permutation];
@scriptName = @scriptName[@permutation];
@scriptContent = @scriptContent[@permutation];
@remoteCommandID = @remoteCommandID[@permutation];
@interpreter = @interpreter[@permutation];
@version = @version[@permutation];
@execTime = @execTime[@permutation];
@stdErr = @stdErr[@permutation];
@stdOut = @stdOut[@permutation];

#print "After sorting : \n";
#print Dumper @rack;

#print Dumper @scriptName;

# All values are ready to be executed in the right order
my $result;
#Prepare the response


for ( my $c = 0; $c < $size; $c++) {
	my $uri = "http://'.$api_url.'/SPOT/provisioning/api/remotecommands/";

#	$REST = 
#build the string
	my $uri_put = $uri.$remoteCommandID[$c];
	my $req = HTTP::Request->new( 'PUT', $uri_put );
	
	$req->header( 'Content-Type' => 'application/json' );

# set custom HTTP request header fields
#This is the directory where linux images reside
	$execTime[$c] = localtime;
	my $lwp = LWP::UserAgent->new(
			timeout               => 10,
			);
	$REST = '{"remotecommandid" : "'.$remoteCommandID[$c].'", "salesorder" : "'.$so[$c]. '", "rack" : "'.$rack[$c].'", "shelf" : "'.$shelf[$c].'", "exectime" : "'.$execTime[$c].'",  ';
		@scheduled_time = split(':', $execTime[$c]);
		if ($exeFlag[$c] == 0 || ($exeFlag[$c] == 100 && $now_string == $scheduled_time[0])) {

			system("chmod 775 ".$scriptName[$c]);
			$now_string = strftime "%H:%M", localtime;

#converting from json to string
			if ( ! $args[$c] eq "")
			{ 
				my %arguments = %{ decode_json($args[$c]) };

				while (my ($key, $value) = each  %arguments) {
					print "$key = $value\n";
				}
				print "arguments sorted by key after decoding:\n";

#Be sure that scalar $list is empty
				$list = '';

				foreach (sort { $a <=> $b } keys(%arguments) )
				{
					print "key: $_ value: $arguments{$_}\n";
					$list .= " $arguments{$_}";
				}
			}

#If list is not initialised (no arguments needed) we put a fake value
			$list //="  foo";

			print "Executing: ".$scriptName[$c].$list."\n";
# Sanitize it before to execute
			`dos2unix $scriptName[$c]`;
#$cmd = $scriptName[$c].$args[$c];

			$cmd = $scriptName[$c].$list;

#print $remoteCommandID[$c]."\n";

# Decide if expect to not wait for
		if ($exeSeq[$c] == 0)
		{	
			# Put the command in execution date on the database to avoid to be executed two times
                        my $TEMP; # hold the temporary reponse
                                $flag = 9;
                        $ret = 9;
                        $TEMP =  $REST.'"executionflag" : "'.$flag.'", "returncode" : "'.$ret.'", "returnstdout" : "The script is going to be executed. The command running is: '.$cmd.'" }';
                $req->content($TEMP);
                my $resp = $lwp->request($req);
                print $req->as_string;
                print Dumper $resp;


			system($cmd);
			$ret = $?/256;
			if ($ret == 0 || $ret == 145 ){
				$flag = ($exeFlag[$c] == 0) ? 1:101;
				$REST = $REST. '"executionflag" : "'.$flag.'", "returncode" : "'.$ret.'", "returnstdout" : "The script output cannot be parsed, only signal error check. The command running is: '.$cmd.'" }';
		}
		else
		{
			$ret = $?/256;
			$flag = ($exeFlag[$c] == 0) ? 2:102;
			$REST = $REST.'"executionflag" : "'.$flag.'", "returncode" : "'.$ret.'", "returnstdout" : "execution FAILED" }'
	}

}
else
{

	$result = `$cmd`;
	$ret = $?/256;
	my $stdout = $result->stdout;
	my $stderr = $result->stderr;
	$stdout =~ s/:/ /g; $stdout =~ s/\"/ /g; $stdout =~ s/{/ /g; $stdout =~ s/}/ /g;
	$stderr =~ s/:/ /g; $stderr =~ s/\"/ /g; $stderr =~ s/{/ /g; $stderr =~ s/}/ /g;

#		print Dumper $stdout;
#	$stdout = to_json $stdout;
	if ($ret == 0 || $ret == 145 ){
#		if ( $result->success ) { 
	$flag = ($exeFlag[$c] == 0) ? 1:101;
	$REST = $REST.'"executionflag" : "'.$flag.'" , "returncode" : "'.$ret.'" , "returnstdout" : "'.$stdout.'", "returnstderr" : "'.$stderr.'"}';  
	}
	else { 
		$flag = ($exeFlag[$c] == 0) ? 2:102;
		$REST = $REST.'"executionflag" : "'.$flag.'" , "returncode" : "'.$ret.'", "returnstdout" : "'.$stdout.'", "returnstderr" : "'.$stderr.'"}';  
}
}
}
elsif ($exeFlag[$c] == 101 && $now_string != $scheduled_time[0]) {
	$flag = 100;
	$REST = $REST.'"executionflag" : "'.$flag.'"}';

	}


$req->content($REST);
my $resp = $lwp->request($req);
print $req->as_string;
print Dumper $resp;
`rm $scriptName[$c]`;

}

