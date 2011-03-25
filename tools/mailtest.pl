#!/usr/bin/perl

use warnings;
use strict;
use MIME::Lite;

my @to = qw(cwh@suse.de);

my $used_configfile = '';

foreach my $conf (qw(~/.moncl /etc/moncl.conf)) {
    my ($file) = glob($conf);
    print "Trying config file $file\n";

    if ( defined($file) && readconfig($file) ) {
        print "Using config file: $file\n";
        $used_configfile = $file;
        last;
    }

    print "Config file: $@\n" if ($@);
}

print send_email( \@to, "eMail Test", "Email versenden funktioniert" )."\n";

sub send_email {
    my ( $to, $subject, $text ) = @_;

    my $to_count = 0;
    if ( ref($to) eq 'ARRAY' ) {
        $to_count = scalar(@$to);
    }
    else {
        $to_count = 1;
    }

    return 0 unless $to_count;

    my $mail = MIME::Lite->new(
        From         => $Cfg::MAIL_FROM,
        To           => $to,
        Subject      => $subject,
        'Message-ID' => msgid($Cfg::MAIL_FROM),
        Precedence   => 'bulk',
        Type         => 'TEXT',
        Data         => $text
    );

    my %auth = ();

    %auth = (
        AuthUser => $Cfg::MAIL_USER,
        AuthPass => $Cfg::MAIL_PASS
    ) if ($Cfg::MAIL_USER);

    eval {
        $mail->send(
            'smtp',
            $Cfg::MAIL_SERVER,
            Timeout => 60,
            Hello   => '127.0.0.1',
            %auth
        );
    };

    print "sending email failed: $@\n" if ($@);

    return $to_count;
}

# Generate an email message-id
sub msgid {
    my $from = shift || 'root@localhost';

    my @timedate = localtime( time() );
    $timedate[4]++;
    $timedate[5] += 1900;

    return sprintf(
        '<%d%02d%02d%02d%02d.%05d.%s>',
        @timedate[ 5, 4, 3, 2, 1 ],
        rand( $timedate[0] * 1694 ), $from
    );
}
