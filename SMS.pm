##############################################################################
#
# SMS.pm - Part of moncl, a email and short message alerting client for
# monitord
# Copyright (C) 2009 Christopher Hofmann <cwh@webeve.de>
#
# ---------------------------------------------------------------------------
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation; either version 2 of the License, or (at your option)
# any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, write to the Free Software Foundation, Inc., 51
# Franklin St, Fifth Floor, Boston, MA 02110, USA
#
###############################################################################

package SMS;

use strict;
use Exporter;
use LWP::Simple;
use Encode;
use URI;
use autouse 'Net::Clickatell';

use vars qw(@ISA @EXPORT);

@ISA    = qw(Exporter);
@EXPORT = qw();

sub send {
  my ($from, $to, $who, $what) = @_;

  if ( $Cfg::SMS_PROVIDER eq 'Clickatell' ) {
    my $clickatell = Net::Clickatell->new( API_ID => $Cfg::CATELL_API_ID,
                                           USERNAME =>$Cfg::CATELL_USER,
                                           PASSWORD =>$Cfg::CATELL_PASS );

    return $clickatell->sendBasicSMSMessage($from,
                                            join(',',@$to),
                                            "$what $who");
  } elsif ( $Cfg::SMS_PROVIDER eq 'SMSKaufen' ) {
    return smskaufen($from, $to, $who, $what);
  }
  else {
    return "Could not find SMS Provider $Cfg::SMS_PROVIDER.";
  }
}

sub smskaufen {
  my ($from, $to, $who, $what) = @_;

  $from = $what;

  my %returnvals = ('100' => 'Dispatch OK',
                    '101' => 'Dispatch OK',
                    '111' => 'IP was blocked',
                    '112' => 'Incorrect login data',
                    '120' => 'Sender field is empty',
                    '121' => 'Gateway field is empty',
                    '122' => 'Text is empty',
                    '123' => 'Recipient field is empty',
                    '129' => 'Wrong sender',
                    '130' => 'Gateway Error',
                    '131' => 'Wrong number',
                    '132' => 'Mobile phone is off',
                    '133' => 'Query not possible',
                    '134' => 'Number invalid',
                    '140' => 'No credit',
                    '150' => 'SMS blocked',
                    '170' => 'Date wrong',
                    '171' => 'Date too old',
                    '172' => 'Too many numbers',
                    '173' => 'Wrong format');

  my $url = "http://www.smskaufen.com/sms/gateway/sms.php";

  my $message = "$what $who";
  my $enc_message = encode( "iso-8859-1", $message );
  my %params = ( id => $Cfg::SMSKAUFEN_USER,
                 pw => $Cfg::SMSKAUFEN_PASS,
                 type => 4,
                 massen => 1,
                 termin => smstime(),
                 empfaenger => join(';',@$to),
                 absender => $from,
                 text => $enc_message );

  my $uri = URI->new($url);
  $uri->query_form( %params );

  #print "$uri\n";

  my $result = get($uri);

  return "($result) ".$returnvals{$result}."\n";
}

sub send_wappush {
  my ($from, $to, $message, $file_url) = @_;

  return 'URL missing' unless $file_url;

  my %returnvals = ('100' => 'Dispatch OK',
                    '101' => 'Dispatch OK',
                    '111' => 'IP was blocked',
                    '112' => 'Incorrect login data',
                    '120' => 'Sender field is empty',
                    '121' => 'Gateway field is empty',
                    '122' => 'Text is empty',
                    '123' => 'Recipient field is empty',
                    '129' => 'Wrong sender',
                    '130' => 'Gateway Error',
                    '131' => 'Wrong number',
                    '132' => 'Mobile phone is off',
                    '133' => 'Query not possible',
                    '134' => 'Number invalid',
                    '140' => 'No credit',
                    '150' => 'SMS blocked',
                    '170' => 'Date wrong',
                    '171' => 'Date too old',
                    '172' => 'Too many numbers',
                    '173' => 'Wrong format');

  my $url = "http://www.smskaufen.com/sms/gateway/sms.php";
  my $enc_message = encode( "iso-8859-1", $message );
  my @return = ();

  foreach my $recipient (@$to) {
      my %params = ( id => $Cfg::SMSKAUFEN_USER,
                     pw => $Cfg::SMSKAUFEN_PASS,
                     type => 9,
                     empfaenger => $recipient,
                     absender => $from,
                     text => $file_url,
                     wapmeldung => $enc_message );

      my $uri = URI->new($url);
      $uri->query_form( %params );

      print "$uri\n";

      my $result = get($uri);
      push @return, "($result) ".$returnvals{$result};
  }

  return join('; ', @return);
}

sub smstime
{
    my $epoch = shift || time();

    my @timedate = localtime($epoch);
    $timedate[4]++;
    $timedate[5] += 1900;

    return(sprintf('%02d.%02d.%d-%02d:%02d', @timedate[3,4,5,2,1]));
}


1;
