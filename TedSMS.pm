package TedSMS;
##!/usr/bin/perl -w

use MIME::Lite;



sub textSMS{
    my $datetime = shift;
    
    my @dt = localtime(time);
  
    

    if( $dt[2] >= 8 && $dt[2] < 17 )
    {
       unless(open( MAIL, "|/usr/sbin/sendmail -t")) {
         print "error.\n";
         warn "Error starting sendmail $!\n";
       }
       else {
        print MAIL "To: email@address.com\n";
        print MAIL "Auto DETECTION - $datetime GMT\n";
        close(MAIL) or warn "Error closing mail: $!\n";
        print "Text message sent.\n";
      }
   }
   else
   {
     print "Not between 8am and 5pm, not sending text.\n";
   }
}
1;

