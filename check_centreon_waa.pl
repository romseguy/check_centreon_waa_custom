#!/usr/bin/perl

################################################################################
# Copyright 2004-2011 MERETHIS
# Centreon is developped by : Maximilien Bersoult under GPL Licence 2.0.
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation ; either version 2 of the License.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
# PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, see <http://www.gnu.org/licenses>.
#
# Linking this program statically or dynamically with other modules is making a
# combined work based on this program. Thus, the terms and conditions of the GNU
# General Public License cover the whole combination.
#
# As a special exception, the copyright holders of this program give MERETHIS
# permission to link this program with independent modules to produce an executable,
# regardless of the license terms of these independent modules, and to copy and
# distribute the resulting executable under terms of MERETHIS choice, provided that
# MERETHIS also meet, for each linked independent module, the terms  and conditions
# of the license of that module. An independent module is a module which is not
# derived from this program. If you modify this program, you may extend this
# exception to your version of the program, but you are not obliged to do so. If you
# do not wish to do so, delete this exception statement from your version.
#
# For more information : contact@centreon.com
#
####################################################################################

use strict;
use warnings;
use Getopt::Long;
use Time::HiRes;
use XML::XPath;
use XML::XPath::XMLParser;
use WWW::Selenium;

our $VERSION = "1.0.2";

my $critical = 0;
my $warning = 0;
my $remote = "";
my $testname = "";
my $directory = "";
my $fulldata = 0;
my $retcode = 3;
my $tmpOk = 1;

##
# Print version and exit
##
sub version {
    print "check_centeron_waa version $VERSION\n";
    exit 0;
}

##
# Print help and exit
##
sub help {
    my ($ret) = @_;
    print <<EOP;
check_centeron_waa -c <critical> -w <warning> -r <remote> -t <testname> -d <directory> [-f]

\t-c|--critical\t\tThe critical time
\t-w|--warning\t\tThe warning time
\t-r|--remote\t\tThe remote control for Selenium
\t-t|--testname\t\tThe test name
\t-d|--directory\t\tThe directory with test files

EOP
    if ($ret =~ /^\d+$/) {
        exit $ret;
    }
    exit 0;
}
# \t-f|--fulldata\t\tSend the HAR data to a remote

sub trim {
  my $string = shift;
  $string =~ s/^\s+//;
  $string =~ s/\s+$//;
  return $string;
}

Getopt::Long::Configure("bundling");
GetOptions(
    "V" => \&version, "version" => \&version,
    "h" => \&help, "help" => \&help,
    "c=f" => \$critical, "critical=f" => \$critical,
    "w=f" => \$warning, "warning=f" => \$warning,
    "r=s" => \$remote, "remote=s" => \$remote,
    "t=s" => \$testname, "testname=s" => \$testname,
    "d=s" => \$directory, "directory=s" => \$directory
    #"f" => \$fulldata, "fulldata" => \$fulldata
);

#
# Check for config file values
#
my $p = XML::Parser->new(NoLWP => 1);

if (-e "$directory/$testname.xml") {
  my $desc = XML::XPath->new(parser => $p, filename => "$directory/$testname.xml");
  our $listIntervalNode = $desc->find('/config/interval');

  # validation
  if ($listIntervalNode->size() eq 0) {
    print "At least one interval to measure has to be set";
    exit 2;
  }

  foreach my $intervalNode ($listIntervalNode->get_nodelist) {
    if ($intervalNode->getAttribute('from') >= $intervalNode->getAttribute('to')) {
      print "Invalid scenario description\n\n";
      exit 2;
    }
  }

  if ($critical eq 0) {
    $critical = $desc->find('/config/critical')->string_value();
  }

  if ($warning eq 0) {
    $warning = $desc->find('/config/warning')->string_value();
  }
}

if ($critical eq 0 or $warning eq 0 or $remote eq "" or $testname eq "" or $directory eq "") {
    print "Missing arguments\n\n";
    help(3);
}

unless (-d $directory) {
    print "The directory $directory does not exists\n\n";
    help(3);
}

unless (-f "$directory/$testname.html") {
    print "The test file $directory/$testname.html does not exist\n\n";
    help(3);
}

#
# Open test file
#
my $xp = XML::XPath->new(parser => $p, filename => "$directory/$testname.html");

my $baseurlNode = $xp->find('/html/head/link[@rel="selenium.base"]');
my $baseurl = $baseurlNode->shift->getAttribute('href');

#
# Find list of actions
#
my $listActionNode = $xp->find('/html/body/table/tbody/tr');

#
# Parse remote
#
my ($remoteHost, $remotePort) = split(/:/, $remote);

#
# Start Selenium RC
#
my $sel = WWW::Selenium->new(
    host => $remoteHost,
    port => $remotePort,
    browser => "*firefox",
    browser_url => $baseurl
);

my $status = 1;
my $action = undef;
my $filter = undef;
my $value = undef;

my $step = 0;
my $stepOk = 0;

$sel->start;

my $start = [ Time::HiRes::gettimeofday( ) ];
my $startStepId = 0;
my $startStep = 0;
my $endStep = 0;
my $perfdata = "";

foreach my $actionNode ($listActionNode->get_nodelist) {
  if ($status) {
    my $listInfos = $xp->find('./td', $actionNode);
    $step += 1;
    ($action, $filter, $value) = $listInfos->get_nodelist;

    if (-e "$directory/$testname.xml") {
      foreach my $intervalNode ($main::listIntervalNode->get_nodelist) {
        if ($intervalNode->getAttribute('from') == $step) {
          $startStep = [ Time::HiRes::gettimeofday() ];
          $startStepId = $step;
        }
      }
    }

    if (trim($action->string_value) eq 'pause') {
      my $sleepTime = 1000;

      if (trim($value->string_value) =~ /^\d+$/) {
        $sleepTime = trim($value->string_value);
      }

      if (trim($filter->string_value) =~ /^\d+$/) {
        $sleepTime = trim($filter->string_value);
      }

      sleep($sleepTime / 1000);
      $stepOk += 1;
    } else {
      $tmpOk = 1;
      eval { $sel->do_command(trim($action->string_value), trim($filter->string_value), trim($value->string_value)) }; $tmpOk = 0 if $@;

      if (!$tmpOk) {
        $status = 0;
      } else {
        $stepOk += 1;
      }
    }

    if (-e "$directory/$testname.xml") {
      foreach my $intervalNode ($main::listIntervalNode->get_nodelist) {
        if ($intervalNode->getAttribute('to') == $step) {
          $endStep = Time::HiRes::tv_interval($startStep);
          my $intervalWarning = ($intervalNode->getAttribute('warning') > 0) ? $intervalNode->getAttribute('warning') : $warning;
          my $intervalCritical = ($intervalNode->getAttribute('critical') > 0) ? $intervalNode->getAttribute('critical') : $critical;

          $perfdata .= "'${startStepId}to${step}'=${endStep}s;${intervalWarning};${intervalCritical} ";
        }
      }
    }
  } else {
    $step += 1;
  }
}
my $end = Time::HiRes::tv_interval($start);

$sel->stop;

my $output = "CHECKWEB ";

if ($status == 0) {
  $retcode = 2;
  $output .= "CRITICAL";
} elsif ($end > $critical) {
  $retcode = 2;
  $output .= "CRITICAL";
} elsif ($end > $warning) {
  $retcode = 1;
  $output .= "WARNING";
} else {
  $retcode = 0;
  $output .= "OK";
}

$output .= " - Execution time = ${end}s - ${stepOk}/${step} steps passed |'time'=${end}s;${warning};${critical} $perfdata\n";

print $output;
exit $retcode;
