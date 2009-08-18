#!/usr/bin/perl -w

use strict;
use IO::Socket;
use MIME::Lite;
use Net::SMS::Clickatell;

my $maxdelta_t = 3;

my $mail_from = 'ffw@goessenreuth.de';
my $mail_server = 'mail.webeve.de';
my $mail_user = 'cwh';
my $mail_pass = 'ZDa!DaH?';
#my $mail_server = 'relay.suse.de';
#my $mail_user = '';
#my $mail_pass = '';

my $catell_api_id = '3187455';
my $catell_user = 'cwhofmann';
my $catell_pass = 'dam0kles';

my %people = ( cwh => { name => 'Christopher Hofmann', phone => '01702636472', email => 'cwh@webeve.de' },
               seggl => { name => 'Markus Matussek', phone => '01718813863', email => 'markus.matussek@glendimplex.de' },
               andrea => { name => 'Andrea Herzog', phone => '015111701351', email => 'la-andi@gmx.de' },
               achim => { name => 'Achim Geyer', phone => '01607634981', email => 'geyer.achim@landkreis-kulmbach.de' },
               xaver => { name => 'Alexander Schneider', phone => '015112446132', email => 'alexander.schneider@novem.de' });

# cwh => { name => '', phone => '', email => '' }

my %loops = ( default => { email => [qw(cwh)] },
	      23154 => { name => 'FF Goessenreuth',
                         email => [qw(cwh seggl achim xaver)],
                         sms => [qw(cwh seggl andrea xaver)] },
              23152 => { name => 'FF Hi. od. La. (152)',
                         email => [qw(cwh)],
                         sms => [qw(cwh)] },
              23153 => { name => 'FF Hi. od. La. (153)',
                         email => [qw(cwh)],
                         sms => [qw(cwh)] } );

# ====================================

my %alarmtypes = ( 0 => 'Melderalarmierung (0)',
                   1 => 'Melderalarmierung (1)',
                   2 => 'Feueralarm',
                   3 => 'Probelalarm',
                   4 => 'Zivilschutzalarm',
                   5 => 'Warnung',
                   6 => 'Entwarnung' );

my %errorcodes = ( '000' => "Unbekannter Fehler", 
                   '001' => "Not logged In",      
                   '002' => "Not Authorized",     
                   '003' => "False Login",        
                   '004' => "Protocoll Error",    
                   '005' => "Not Implemented",    
                   '006' => "Hardware Fault",     
                   '007' => "Write Fault",        
                   '008' => "Version Error",      
                   '009' => "Function deactivated" );

my @wdays = qw(So Mo Di Mi Do Fr Sa);

# ------------------------------------

my $socket = IO::Socket::INET->new( PeerAddr => 'localhost',
                                    PeerPort => 9333,
                                    Proto => 'tcp',
                                    Type => SOCK_STREAM )
    or die("Could not connect: $@\n");

$socket->autoflush(1);
$/ = "\r\n";

sub command
{
    print $socket $_[0].$/;
}

sub timefmt
{
    my $epoch = shift;

    my @timedate = localtime($epoch);
    $timedate[4]++;
    $timedate[5] += 1900;
    $timedate[6] = $wdays[$timedate[6]];

    return(sprintf('%s, %02d.%02d.%d %02d:%02d:%02d', @timedate[6,3,4,5,2,1,0]));
}

sub textdecode
{
    my $code = shift;
    my $decode = '';
    my $i = 0;

    while( my $chr = substr( $code, $i, 2 ) )
    {
        $decode .= chr(hex($chr));
	$i+=2;
    }

    return $decode;
}

sub msgid
{
    my $from = shift || 'root@localhost';

    my @timedate = localtime(time());
    $timedate[4]++;
    $timedate[5] += 1900;

    return sprintf('<%d%02d%02d%02d%02d.%05d.%s>', @timedate[5,4,3,2,1], rand($timedate[0]*1694), $from);
}

sub send_email
{
    my ($loop, $type, $time, $file ) = @_;

    my $loopdata = $loops{$loop} || $loops{default};

    my $who = $loopdata->{name} || $loop;
    my $what = $alarmtypes{$type} || $type;
    my $to = $loopdata->{email} || [];

    my $text = sprintf( "%s: %s %s", timefmt($time), $what, $who);

    my $mail = MIME::Lite->new( From => "FF Alarmierung <$mail_from>",
                                Subject => "$what $who",
                                'Message-ID' => msgid($mail_from),
                                Precedence => 'bulk',
                                Type => 'multipart/mixed' );

    my @to = grep {ref($people{$_}) && $people{$_}->{email} && ($_ = $people{$_}->{email})} @$to;

    if(@to > 0)
    {
        $mail->add("To" => \@to);
    }
    else
    {
        $mail->add("To" => $loops{default}->{email}||[]);
    }

    $mail->attach( Type => 'TEXT',
                   Data => $text );

    if( $file )
    {
        $mail->attach( Type => 'audio/mpeg',
                       Path => $file );
    }

    #print $mail->as_string();
    $mail->send('smtp',
		$mail_server,
		Timeout => 60,
		Hello => '127.0.0.1',
                AuthUser => $mail_user,
		AuthPass => $mail_pass);
}

sub send_sms
{
    my ($loop, $type, $time) = @_;

    my $loopdata = $loops{$loop} || $loops{default};

    my $who = $loopdata->{name} || $loop;
    my $what = $alarmtypes{$type} || $type;
    my $to = $loopdata->{sms} || [];

    my $catell = Net::SMS::Clickatell->new( API_ID => $catell_api_id );
    $catell->auth( USER => $catell_user,
                   PASSWD => $catell_pass );

    my $count = 0;

    foreach my $person (@$to)
    {
        next if !ref($people{$person});
        my $phone = $people{$person}->{phone};

        print "\tSMS to $phone with text \"$what $who\"\n";
        $count += $catell->sendmsg(TO => $phone,
				   MSG => "$what $who");
    }

    return $count;
}

my %lastalarm = ();
my $recordingstart;

while( my $line = <$socket> )
{
    chomp( $line );
    my ( $cmd, @params) = split(/:/, $line );

    if( $cmd eq '300' )
    {
        my %alarmdata = ();
        @alarmdata{qw(time channel loop type text)} = @params;

        # 0    1                 2               3                        4
        # Zeit:Kanalnummer(char):Schleife(text5):Sirenenalarmierung(char):Text

	my $loopdata = $loops{$alarmdata{loop}} || $loops{default};
	my $who = $loopdata->{name} || $alarmdata{loop};

        if( $alarmdata{time} - ($lastalarm{time}||0) <= $maxdelta_t && $alarmdata{loop} == $lastalarm{loop} )
        {
            # trigger recording
            my $duration = 20;
            $duration = time() - $recordingstart if(defined($recordingstart));
            command("204:$alarmdata{channel}:$duration");

	    # print message to STDOUT
            my $msg = sprintf( "%s: %s %s", timefmt($alarmdata{time}), $alarmtypes{$alarmdata{type}}, $who);
            print $msg."\n";

	    # send emails
            send_email($alarmdata{loop}, $alarmdata{type}, $alarmdata{time});
            print "\tsent mail\n";

	    #send sms
            my $smscount = send_sms($alarmdata{loop}, $alarmdata{type}, $alarmdata{time});
            print "\tsent $smscount sms\n";

            #reset lastalarm
            %lastalarm = ();
        }
        else
        {
            print timefmt($alarmdata{time}).": Einzelnes Quintett $who\n";
            %lastalarm = %alarmdata;
        }
    }
    elsif( $cmd eq '104' )
    {
        if( $params[1] == 0 )
        {
            $recordingstart = undef;
            print "Aufname beendet: $params[2]\n";
        }
        elsif( $params[1] == 1 )
        {
            $recordingstart = time();
            print "Aufname gestartet: $params[2]\n";
        }
        elsif( $params[1] == 2 )
        {
            print "Aufname verlängert: $params[2]\n";
        }
    }
    elsif( $cmd eq '101' )
    {
        print "Fehler: ".$errorcodes{$params[0]}."\n";
    }
    else
    {
        print "$line\n";
    }
}

close($socket);
