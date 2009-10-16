#!/usr/bin/perl -w

use strict;

open(FILE, "</tmp/srvaddr");
my $addr = <FILE> || '127.0.0.1';
close(FILE);

if( $ARGV[0] && $ARGV[0] eq 'set' && $ENV{'REMOTE_ADDR'} ne $addr )
{
    open(FILE, ">/tmp/srvaddr");
    print FILE $ENV{'REMOTE_ADDR'};
    close(FILE);
}


print "Content-type: text/html\n\n";
print "$addr\n";


