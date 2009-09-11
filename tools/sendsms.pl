#!/usr/bin/perl -w

use strict;
use Net::Clickatell;

my $sms_from = '491702636472';
my $catell_api_id = '3187455';
my $catell_user = 'cwhofmann';
my $catell_pass = 'dam0kles';

my %people = ( cwh => { name => 'Christopher Hofmann', phone => '01702636472', email => 'cwh@webeve.de' },
               seggl => { name => 'Markus Matussek', phone => '01718813863', email => 'markus.matussek@glendimplex.de' },
               andrea => { name => 'Andrea Herzog', phone => '015111701351', email => 'la-andi@gmx.de' },
               achim => { name => 'Achim Geyer', phone => '01607634981', email => 'geyer.achim@landkreis-kulmbach.de' },
               xaver => { name => 'Alexander Schneider', phone => '015112446132', email => 'alexander.schneider@novem.de' },
               rainer => { name => 'Rainer Hartmann', phone => '01604616195', email => '' },
               langers => { name => 'Michael Hartmann', phone => '01717788775', email => 'harmic80@webeve.de' },
               langers_arbeit => { name => 'Michael Hartmann', phone => '', email => 'Michael.Hartmann@fob.lsv.de' },
               langerswolfgang => { name => 'Wolfgang Hartmann', phone => '01605234235', email => '' },
               gernot => => { name => 'Gernot Geyer', phone => '01709233287', email => '' },
               schlaubi => { name => 'Markus Schneider', phone => '01604434387', email => '' });

# cwh => { name => '', phone => '', email => '' }

my %loops = ( default => { email => [qw(cwh)] },
	      23154 => { name => 'FF Goessenreuth',
                         email => [qw(cwh seggl achim xaver langers langers_arbeit)],
                         sms => [qw(cwh seggl andrea xaver rainer langers langerswolfgang)] },
              23152 => { name => 'FF Hi. od. La. (152)',
                         email => [qw(cwh)],
                         sms => [qw(cwh)] },
              23153 => { name => 'FF Hi. od. La. (153)',
                         email => [qw(cwh)],
                         sms => [qw(cwh)] },
              23139 => { name => 'FF Marktleugast',
                         email => [],
                         sms => [] },
              23598 => { name => 'Notfallseelsorge',
                         email => [],
                         sms => [] },
              23591 => { name => 'THW',
                         email => [],
                         sms => [] } );

sub send_sms
{
    my ($loop, $msg) = @_;

    my $loopdata = $loops{$loop} || $loops{default};

    my $to = $loopdata->{sms} || [];

    my $clickatell = Net::Clickatell->new( API_ID => $catell_api_id,
                                           USERNAME =>$catell_user,
                                           PASSWORD =>$catell_pass );

    my @to = grep {ref($people{$_}) && $people{$_}->{phone} && ($_ = $people{$_}->{phone})} @$to;

    if(@to)
    {
        print $clickatell->sendBasicSMSMessage($sms_from,
                                               join(',',@to),
                                               $msg)."\n";
    }
}

my $loop = shift @ARGV;
my $msg = join(' ', @ARGV);

send_sms($loop, $msg);

#print $loop, $msg, "\n";
