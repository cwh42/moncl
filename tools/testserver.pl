#!/usr/bon/perl -w

use strict;
use IO::Socket;

my $server_port = 9333;

my $server = IO::Socket::INET->new(LocalPort => $server_port,
                                   Type => SOCK_STREAM,
                                   Reuse => 1,
                                   Listen => 10 )
    or die("Cannot open port $server_port: $@\n");

my %loop = ( loop => '23152',
             channel => 1 );

while (my $client = $server->accept())
{
    foreach (0,3)
    {
        my $msg = join(':', 300, time(), @loop{qw(channel loop)}, $_, 'msg')."\r\n";
        print $msg;
        print $client $msg;
        sleep(1);
    }
}

close($server);
