#!/usr/bin/perl -w

use strict;
use Net::SMS::Clickatell;

my $catell_api_id = '1563210';
my $catell_user = 'cwhofmann';
my $catell_pass = 'dam0kles';
my $catell = Net::SMS::Clickatell->new( API_ID => $catell_api_id );
$catell->auth( USER => $catell_user,
               PASSWD => $catell_pass );

my $phone = '491702636472';

my $count = $catell->sendmsg( TO => $phone,
                              MSG => 'Sending SMS seems to be working.' );

print "Sent $count message(s)\n";
