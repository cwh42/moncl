#!/usr/bin/perl -w

use strict;

my $DNSUPDATE = 1;

my $HOSTNAME = 'alarm.goessenreuth.de';
my $TTL = 20*60;

open(FILE, "</tmp/srvaddr");
my $addr = <FILE> || '127.0.0.1';
close(FILE);

if( $ARGV[0] && $ARGV[0] eq 'set' && $ENV{'REMOTE_ADDR'} ne $addr )
{
    $addr = $ENV{'REMOTE_ADDR'};

    open(FILE, ">/tmp/srvaddr");
    print FILE $addr;
    close(FILE);

    if($DNSUPDATE)
    {
        my $pid = open(NSUP, "|-", "nsupdate") or die("Could not fork: $!\n");

        while( <main::DATA> )
        {
            s/(\$\w+)/$1/gee;
            print NSUP $_; 
        }

        close(NSUP);
    }
}


print "Content-type: text/html\n\n";
print "$addr\n";

__END__
update delete $HOSTNAME A
update add $HOSTNAME $TTL A $addr
send
