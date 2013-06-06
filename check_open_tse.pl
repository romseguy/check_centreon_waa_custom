#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Long;
use IO::Socket::INET;

my $critical = 0;
my $warning = 0;
my $remote = "";
my $nbrOfTest = 1;
my $typeOfTest = "";
my $retcode = 0;

##
# Print help and exit
##
sub help {
    my ($ret) = @_;
    print <<EOP;
check_open_tse -c <critical> -w <warning> -r <remote> -n <nbrOfTest> -t <typeOfTest>

\t-c|--critical\t\tThe critical time
\t-w|--warning\t\tThe warning time
\t-r|--remote\t\tThe remote control
\t-n|--number\t\tNumber of test attempts
\t-t|--type\t\tType of the test

EOP
    if ($ret =~ /^\d+$/) {
        exit $ret;
    }
    exit 0;
}

Getopt::Long::Configure("bundling");
GetOptions(
    "h" => \&help, "help" => \&help,
    "c=f" => \$critical, "critical=f" => \$critical,
    "w=f" => \$warning, "warning=f" => \$warning,
    "r=s" => \$remote, "remote=s" => \$remote,
    "n=f" => \$nbrOfTest, "number=f" => \$nbrOfTest,
    "t=s" => \$typeOfTest, "type=s" => \$typeOfTest
);

#
# Parse remote
#
my ($remoteHost, $remotePort) = split(/:/, $remote);

# flush after every write
$| = 1;

my ($socket, $client_socket);

$socket = new IO::Socket::INET (
PeerHost => $remoteHost,
PeerPort => $remotePort,
Proto => 'tcp',
) or die "ERROR in Socket Creation : $!\n";

my $data = "mGo," . $nbrOfTest . "," . $typeOfTest;
print $socket "$data\n";
$socket->send($data);

# $data = <$socket>;
# $socket->recv($data,1024);
# print "Received from Server : $data\n";

$socket->close();

exit $retcode;
