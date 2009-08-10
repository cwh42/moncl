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

my $catell_api_id = '1563210';
my $catell_user = 'cwhofmann';
my $catell_pass = 'dam0kles';

my %loops = ( default => { emails => [qw( cwh@webeve.de )],
			   numbers => [qw( 491702636472 491718813863 )] },
	      23154 => { name => 'FF Goessenreuth',
                         emails => [qw( cwh@webeve.de
                                        markus.matussek@glendimplex.de
                                        geyer.achim@landkreis-kulmbach.de
                                        alexander.schneider@novem.de )],
                         numbers => [qw( 491702636472 )] },
              23152 => { name => 'FF Hi. od. La. (152)',
                         emails => [qw( cwh@webeve.de )],
                         numbers => [qw( 491702636472 )] },
              23153 => { name => 'FF Hi. od. La. (153)',
                         emails => [qw( cwh@webeve.de )],
                         numbers => [qw( 491702636472 )] } );

# ====================================

my %alarmtypes = ( 0 => 'Melderalarmierung (0)',
                   1 => 'Melderalarmierung (1)',
                   2 => 'Feueralarm',
                   3 => 'Probelalarm',
                   4 => 'Zivilschutzalarm',
                   5 => 'Warnung',
                   6 => 'Entwarnung' );

my @wdays = qw(So Mo Di Mi Do Fr Sa);

# ------------------------------------

my $catell = Net::SMS::Clickatell->new( API_ID => $catell_api_id );
$catell->auth( USER => $catell_user,
               PASSWD => $catell_pass );

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

    return(sprintf('%d-%02d-%02d (%s) %02d:%02d:%02d', @timedate[5,4,3,6,2,1,0]));
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
    my $to = $loopdata->{emails};

    my $text = sprintf( "%s: %s %s", timefmt($time), $what, $who);

    my $mail = MIME::Lite->new( From => "FF Alarmierung <$mail_from>",
                                Subject => "$what $who",
                                'Message-ID' => msgid($mail_from),
                                Precedence => 'bulk',
                                Type => 'multipart/mixed' );

    if(@$to > 0)
    {
        $mail->add("To" => $to);
    }
    else
    {
        $mail->add("To" => $loops{default}->{emails}||[]);
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
    my $to = $loopdata->{numbers};

    my $count = 0;

    foreach my $phone (@$to)
    {
        $count += $catell->sendmsg(TO => $phone,
				   MSG => "$what $who");
    }

    return $count;
}

my @lastalarm = ();
my $recordingstart;

while( my $line = <$socket> )
{
    chomp( $line );
    my ( $cmd, @params) = split(/:/, $line );

    if( $cmd eq '300' )
    {
        # 0    1                 2               3                        4
        # Zeit:Kanalnummer(char):Schleife(text5):Sirenenalarmierung(char):Text

	my $loopdata = $loops{$params[2]} || $loops{default};
	my $who = $loopdata->{name} || $params[2];

        if( $params[0] - ($lastalarm[0]||0) <= $maxdelta_t && $params[2] == $lastalarm[2] )
        {
            # trigger recording
            my $duration = 20;
            $duration = time() - $recordingstart if(defined($recordingstart));
            command("204:1:$duration");

	    # print message to STDOUT
            my $msg = sprintf( "%s: %s %s", timefmt($params[0]), $alarmtypes{$params[3]}, $who);
            print $msg."\n";

	    # send emails
            send_email($params[2], $params[3], $params[0]);
            print "\tsent mail\n";

	    #send sms
            my $smscount = send_sms($params[2], $params[3], $params[0]);
            print "\tsent $smscount sms\n";

            #reset lastalarm
            @lastalarm = ();
        }
        else
        {
            print timefmt($params[0]).": Einzelnes Quintett $who\n";
        }

        @lastalarm = @params;
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
    else
    {
        print "$line\n";
    }
}

close($socket);
