package TedStatus;

use MIME::Lite;
use Date::Parse;
use Date::Format;

###############################################################################
#  This software is in the public domain because it contains materials
#  that originally came from the United States Geological Survey, 
#  an agency of the United States Department of Interior. For more 
#  information, see the official USGS copyright policy at 
#  http://www.usgs.gov/visual-id/credit_usgs.html#copyright
###############################################################################

###############################################################################
# status_generate:
#  parameters: todays date (maybe previous day?)
#  return: void
#  notes: 
###############################################################################
sub status_generate 
{
   my $today = shift;
   my @datebr = split(/_/,$today);
   my $todayf = "$datebr[0]/$datebr[1]/$datebr[2]";
   my $yd = $datebr[2] - 1;    #### THIS WON"T WORK FOR END OF MONTH!!!
   my $datebrday = "$datebr[0]_$datebr[1]_$yd";
   print "$datebrday\n";
   my $return_value = 1;
   my $logcount;
   my @dayte;
   my $my_mean;
   my (@logs,$log,@z_ss,@z_es,@avlats,@maxlats,@trigs,@alerts,@diffs,%tt,$delay,@delays,$ii,@geoss,$avcount,@avcounts,$my_count);
   open STATUS, ">./Emails/status_$today.txt" or die "PERL could not create email text\n";
   {
#      my @logs = `ls ./Logs/Tedect_$today*`;
      my @logs = `ls ./Logs/Tedect_$datebr[0]_$datebr[1]_*`;
      chomp(@logs);
      foreach $log(@logs)
      {
        @dayte = split(/_/,$log);
       # We want 12:00 previous day up to 11:59 of today
        if(($dayte[3] == $yd && $dayte[4] >= 12) || $dayte[3] == $datebr[2])
        {
           print "pulling from Log: $log\n";
           open INFILE, "$log" or die "Perl could not open logs";
           $logcount = $logcount+1;
           while (<INFILE>)
           {
              if($_ =~ /z_start: (.*)\./)
              { 
                 push(@z_ss, $1);
              }
              elsif($_ =~ /z_end: (.*)\./) 
              {
                  push(@z_es, $1);
                  $diff = str2time($1) - str2time($z_ss[$#z_ss]);
                  $format = 'MM:SS';
                  push(@diffs, time2str('%M:%S',$diff));
              }
              elsif($_ =~ /avlatency: (.*)/) 
              {
                 chomp($1);
                 push(@avlats, $1);
                  print "av: $1\n";
              }
              elsif($_ =~ /maxlatency: (.*)/) 
              {
                 chomp($1);
                 push(@maxlats, $1);
              }
              elsif($_ =~ /tweet_count: (.*)/)
              {
                 chomp($1);
                 $avcount = $1/60;
                 push(@avcounts, $avcount);
              }
   
              elsif($_ =~ /Trig\stime:\s(.*)\..*Computer\stime:\s(\d\d\d\d-\d\d-\d\d\s\d\d:\d\d:\d\d)\./) 
              {
                 chomp($1);
                 chomp($2);
                 $tt{$1}=$2;
                 $delay = str2time($2) - str2time($1);
                 push(@delays,time2str('%M:%S',$delay));
              }
              elsif($_ =~ /TopGEOS:\s(.*)/)
              {
                 chomp($1);
                 push(@geoss,$1);
              }
           }
        }
      }
       ## Now that we've collected latencies, average them
       if(scalar(@avlats)>=1)
       {
          $my_mean = eval(join("+",@avlats)) / scalar(@avlats);
          print "$my_mean\n";
       }
#       else
#       {
#          my $my_mean = 0.0009;
#       }
       ## Find the max latency out of all per-hour-max-latencies
       my $my_max = 0.009;
       if(@maxlats>=1)
       {
           foreach $max(@maxlats)
           {
              if($max > $my_max)
              {  $my_max = $max; }
           }
       }
 
       if(scalar(@avcounts)>=1)
       {
          $my_count = eval(join("+",@avcounts)) / scalar(@avcounts);
          print "$my_count\n";
       }


       $logcount = $logcount - 1;
       printf "%s %.1f %.1f %.0f \n", $todayf, $my_mean, $my_max, scalar(@z_ss);
       printf STATUS"%s %.1f %.1f %.0f \n\n", $todayf, $my_mean, $my_max, scalar(@z_ss);
       print STATUS "Status of Application:\n";
       print STATUS "(Log spans previous 24 hours, from 12:00 GMT previous day to 11:59 GMT today)\n\n";
       print STATUS "The tedect system was restarted $logcount times\n\n";
       print STATUS "Caught ",scalar(keys %tt)." events.\n"; 
       print STATUS " Alert Times                 |   Trigger Times      --> delay:\n";
       #while(($tr,$al) = each(sort keys %tt))
       $ii = 0;
       foreach $tr (sort keys %tt)
       {
          print STATUS "$geoss[$ii]\n";
          print STATUS " $tt{$tr}  |  $tr  --> $delays[$ii]\n";
          $ii++;
       }


       print STATUS "\n";
       print STATUS "Had ",@z_ss." cases of a >5min dropout:\n";
       for($ii=0;$ii<@z_ss;$ii++)
       {
         print STATUS " $z_ss[$ii]   --> for $diffs[$ii] \n";
       }

       print STATUS "\n";
       printf STATUS "Average Latency: %.1f\n",$my_mean;
       printf STATUS "Max Latency: %.1f\n",$my_max;
       printf STATUS "Average Tweets/min: %.1f\n",$my_count;
       close STATUS;
   }

   return $return_value;
}
1;        


             
###############################################################################
# notify:
#  parameters: event_id - id of the event to remove
#  return: void
#  notes: 
###############################################################################
sub email_status 
{
   my $today = shift;
   my $return_value = 1;
   open STATUS, "./Emails/status_$today.txt" or die "PERL could not create email text\n";
   my @lines = <STATUS>;  #First line will be a timestamp
   my $first_line = $lines[0];
   chomp($first_line);
    {
     
       ## Setup host, target addres, and subject
       my $host = 'localhost';
       my $address = 'email@address.com';
       my $subject = "[LOG Tedect PROD] $first_line";
 
    ### Load text file for message body
    my $text = join '', @lines[1..scalar(@lines)+1];
 
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
 
 
       print "sending status email...\n";
       ## send
       $msg->send("smtp", $host, Timeout=>90); 
       print "message sent.\n";
 
    }
 
    return $return_value;
 }
 
 
1;
 
