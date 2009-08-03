#!/usr/bin/perl -w

use strict;

if( $ARGV[0] && $ARGV[0] eq 'set' )
{
    open(FILE, ">/tmp/srvaddr");
    print FILE $ENV{'REMOTE_ADDR'};
    close(FILE);
}

open(FILE, "</tmp/srvaddr");
my $addr = <FILE> || '127.0.0.1';
close(FILE);

print "Content-type: text/html\n\n";
print "$addr\n";


