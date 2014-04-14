package TedEmail;
##!/usr/bin/perl -w

use MIME::Lite;

###############################################################################
#  This software is in the public domain because it contains materials
#  that originally came from the United States Geological Survey, 
#  an agency of the United States Department of Interior. For more 
#  information, see the official USGS copyright policy at 
#  http://www.usgs.gov/visual-id/credit_usgs.html#copyright
###############################################################################

###############################################################################
# notify:
#  parameters: event_id - id of the event to remove
#  return: void
#  notes: 
###############################################################################
sub email_all 
{
   my $datetime = shift;
   my $topg = shift;
   my $totnu = shift;
   my $return_value = 1;
   my $subject = "[Tedect]";
   {
         open(EMAILS, "./email_list.txt");
         my @ems;
         while(<EMAILS>)
         {
            chomp;
            push(@ems, $_);
         }
         my $address = join(",",@ems); 
        print "printing to: $address\n";
         my $host = 'localhost';
        if ($topg !~ 'None')
        {   $subject = "$topg $totnu $datetime [Tedect]";}
        else
        {   $subject = "Location undetermined $datetime [Tedect]"; }
        

   
      ### Load text file for message body
      open(BODY_IN, "./email.txt");
      my @tmp = <BODY_IN>;
      my $text = join '', @tmp;
   
         my $msg = MIME::Lite->new(
            From => "twitterID",
            To => $address,
            Type => "multipart/mixed",
            Subject => $subject,
         );
         $msg->attach(
           Type     =>'TEXT',
           Data     =>$text
         );
   #      $msg->attach(
   #         Type =>'TEXT',
   #         Path =>$outfile,
   #         Filename =>$outfile,
   #         Disposition =>'attachment'
   #      );
   
   
         print "sending...\n";
         ## send
         $msg->send("smtp", $host, Timeout=>90); 
         print "message sent.\n";
   
      
      my @td = gmtime(time);	
        # Returns: ss mm hh DD MM YYYY day_in_year day_of_week daylight_sav
      my @year = 1900 + $td[5];
      my @month = 1 + $td[4];
      my $savename = "./Emails/TedectEMAIL_$year[0]_$month[0]_$td[3]_$td[2]_$td[1]_$td[0].txt";

      

      my $result = `mv email.txt $savename`; 

   }

   return $return_value;
}


###############################################################################
# follow:
#  notes: 
###############################################################################
sub follow
{
   my $subj = shift;
   my $return_value = 1;
   {
##       ### Load text file for message body
       open(FOLL_IN, "./followup.txt");
       my @tmp = <FOLL_IN>;
       my $text = join '', @tmp;
##    
          my $msg = MIME::Lite->new(
             From => "twitterID",
             To => $address,
             Type => "multipart/mixed",
             Subject => $subj,
          );
          $msg->attach(
            Type     =>'TEXT',
            Data     =>$text
          );
          $msg->attach(
            Type     =>'image/png',
            Path     =>'tweetgram.png',
            Filename =>'tweetgram.png',
            Disposition => 'attachment'
          );
          $msg->attach(
            Type     =>'image/png',
            Path     =>'map.png',
            Filename =>'map.png',
            Disposition => 'attachment'
          );
##    
##    
          print "sending followup...\n";
##          ## send
          $msg->send("smtp", $host, Timeout=>90); 
          print "message sent.\n";

      
      my @td = gmtime(time);	
        # Returns: ss mm hh DD MM YYYY day_in_year day_of_week daylight_sav
      my @year = 1900 + $td[5];
      my @month = 1 + $td[4];
      my $savename = "./Emails/Followup_$year[0]_$month[0]_$td[3]_$td[2]_$td[1]_$td[0].txt";
      my $result = `mv followup.txt $savename`; 

   }
   return $return_value;
}
1;
