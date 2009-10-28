#!/usr/bin/perl -w

use strict;

my $DNSUPDATE = 1;

my $HOSTNAME = 'alarm.goessenreuth.de';
my $FILE = '/tmp/srvaddr';
my $TTL = 20*60;

open(FILE, "</tmp/srvaddr");
my $addr = <FILE> || '127.0.0.1';
close(FILE);

if( $ARGV[0] && $ARGV[0] eq 'set' )
{
    open(FILE, ">$FILE");
    print FILE $ENV{'REMOTE_ADDR'};
    close(FILE);

    if($DNSUPDATE && $ENV{'REMOTE_ADDR'} ne $addr ))
    {
        my $pid = open(NSUP, "|-", "nsupdate") or die("Could not fork nsupdate: $!\n");

        while( <main::DATA> )
        {
            s/(\$\w+)/$1/gee;
            print NSUP $_; 
        }

        close(NSUP);
    }
}


print "Content-type: text/plain\n\n";
print "$addr\n";

__END__
update delete $HOSTNAME A
update add $HOSTNAME $TTL A $addr
send
