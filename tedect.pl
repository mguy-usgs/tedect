#!/usr/bin/perl 
# version 1.0.2
#  New in this version: word count filter

# version 1.0.3
#  New in this version: new cleaner format

#version 1.0.4
# New in this version: self geocoding

#version 1.0.41
# Improved geocoding, including reverse geocoding.
# Now requires Text::unidecode

#version 1.0.42
# Improved geocoding, better handling accents

#version 1.0.5
# Improved followup handling. requires TedFollow.pm

#version 1.1.0
# Ready for PROD deployment. Includes structural changes for followup emails.
#  (though followup only on DEV)

#version 1.1.1
# Changed format of emails. 
# Combined tweet-printing and tweet-geocoding into a single process
# Added utf-8 encoding before geocoding

#version 1.1.2
# Followup handling is now entirely separate.
#  (queries database independent of main calling program)

#version 1.2.0
# Update geocoding to match Yahoo's YQL. Old style depreciated.

# Note: newer versions exist. Includes threading for geocoding communication
#  Includes XML style output for passing to web interface.
#  These versions however require higher maintenance...

use strict;
use Time::HiRes qw( gettimeofday tv_interval );
use DBI;
use DBD::Pg;
use POSIX;
## Requires the above three packages to be installed!
## also requires PostgreSQL to be installed!
##  
## perl -MCPAN -e 'install Bundle::DBI'
## perl -MCPAN -e 'install DBD::Pg'
## perl -MCPAN -e install 'Time::HiRes'
##
## Visit http://search.cpan.org/~timb/DBI/lib/Bundle/DBI.pm
## Visit http://search.cpan.org/~rudy/DBD-Pg/Pg.pm
## for more info

use TedEmail;
#use TedSMS;
use TedStatus;
use TedTools;
use TedTweet;
#use TedFollow;
## Requires the above three packages to sit in the same directory.

## Setup:  
##   Must have a ./Logs/
##   Must have a ./Emails/ 
##   Must have a ./email_list.txt   to define email recipients

## Platform Specific:
##   SQL database credentials (about 20 lines down)
##   Email server to use -- see TedEmail.pm

## Tweakable:
##   Filter words (top of script)
##   Sensitivity (mm, CC, llta, lsta, at top of script)
##   Verbosity (flag, top of script)

## Running it:
##   Usually initiated with:
##
##   nohup perl tedect.pl &

## What it does:
##   Loop runs every 1 second, asks database how many *new* tweets.
##   When a 5-sec bin is ready and full (tweets exist beyond it),
##   it will count those tweets. It looks for a "spike" by comparing
##   recent bins (Short Term Average) to background noise (Long 
##   Term Average). When this ratio, STA/LTA is big enough, it sends
##   an email claiming a possible earthquake. 


## Variable Declaration
  ## Not all variables pre-declared, just those inside the runnng loop.
my ($t1, $et, $lta, $ltc, $sta, $stc, $chrf, $trigable,$trig_time,@ts,@tt,$ov,$query_handle,$query,$twitter_id,$date_created,$twitter_date,$text,$to_be_geo_located,$lat,$lon,$loc_string,$loc_qual,$location_type,$ranget,$ovq,@datestamp,@times,$date_f,$ti2,$f1,$f2,$ovh,$tic,@t1sp,@t1sp1,@t1sp2,@t1sec,$t2,@t2sp,@t2sp1,@t2sp2,@t2sec,$t3,@t3sp,@t3sp1,@t3sp2,@t3sec,$tdt1,$tdt2,$tdt3,$ttm1,$ttm2,$ttm3,$query,$qh,$first_line,$log_store,$result,@tdl,$ticb,$type,$z_check,$z_start,$z_end,$wasdrop,$isdrop,$lastdrop,$avlayt,$maxlayt,$hr,$today,$ticnf,@tsnf,@month,@td,@year,$words,$tich2,$pkchrf,$topgeo,$bench,$b1,$totnum,$mxstc,$tic_all,$ff3,@twords,@lwords,$recording,$flat,$flon,$floc,$flqual,$mlat,$mlon,$blat,$blon,$geolist,$tweet_count,$rawref,$laloref,$geolistref);

# The database collects all tweets, but we only use certain ones for the trigger.
# Filter words for tweet searching, regexp style
my $filt = '( RT |@|#|http|[0-9]|song|drill|predict|MundosOpuestos)';

# Have to define filt for both SQL call and Perl regex. This is not ideal, and could be improved.
#my @filt2 = (" RT ","@","#","http","song","drill","predict","MundosOpuestos","0","1","2","3","4","5","6","7","8","9","0");

my $wcut = 8; # number of words required for a tweet to count for trigger

## Adjustable parameters for the STA / LTA ratio.
##    C(t)  =  STA  /  (LTA * mm) + CC
##   
##    trigger when C(t) > 1
##
my $mm = 2;
my $CC = 12;
my $llta = 30;  #minutes to count as "long term average"
my $lsta = 1;   #minutes to count as "short term average"

# We bin every 5 seconds. ("dt" in the paper). 
#   This is currently hard-coded in.

my $verb = 0;  #verbose mode for output

# log_write will be current log file.
my $log_write = "./log_write.txt";
if (-e $log_write)    #Need to move previous day's log to ./Logs
{
  open LOGFILE, $log_write or die "error loading previous log";
  $first_line = <LOGFILE>;  #First line will be a timestamp
  close LOGFILE;
  chomp($first_line);
  $log_store = "./Logs/Tedect_$first_line.txt";
  my $result = `mv $log_write $log_store`;
} 

#Create a logfile, using PERL timestamp in title
&startlog; #subroutine at bottom of file, prints stuff at top of log


###### Connect to Database #####
 my $connect = DBI->connect('DBI:Pg:dbname=name;host=127.0.0.1','usr','passwd',{'RaiseError' => 1, pg_server_prepare => 1});  # PROD credentials

 print LOGFILE "Connected to TED SQL server.\n";
################################


# We can prepare most SQL queries (and handles) ahead of time.
#  (this is necessary to interface PERL with PGSQL and may actually be faster)
#
#  All communication with SQL follows this format:
#     1. define query
#     2. prepary query with the database
#     3. execute query
#     4. fetch results
my $tquer = "select now() at time zone 'UTC';";
my $tqh = $connect->prepare($tquer);  # Prepare time query handle (tqh)
$tqh->execute();
my $sqlt = $tqh->fetchrow_array();   # This 4th line finally gets the data
# sqlt is the current time (according to sql database).
#
# Currently this script sits on the same machine as its database... but should
#  they ever be separate, this would help sync the two.


#This is the actual counting query
#   In this case, we only prepare it. The '?' can be filled in with times later
my $ticq = "select count(twitter_id) from status where twitter_date > ? and twitter_date < ? and text !~ '$filt'";
my $tich = $connect->prepare($ticq);

my $ticq2 = "select text from status where twitter_date > ? and twitter_date < ? and text !~ '$filt'";
my $tich2 = $connect->prepare($ticq2);

my $ticq_nq = "select count(twitter_id) from status where twitter_date > ? and twitter_date < ?";
my $tich_nq = $connect->prepare($ticq_nq);

my $fullquer = "select twitter_id, date_created, twitter_date, text, to_be_geo_located, coalesce(st_y(status.location),999) as lat, st_x(status.location) as lon, coalesce(location_string,'None'), location_quality, location_type from status where twitter_date > ? and twitter_date < ? order by twitter_date asc";
my $full_handle = $connect->prepare($fullquer);

## The first calling time is 31 minutes before "now"
## Need to fill enough for LTA and STA
my $ti1 = "select timestamp '$sqlt' - interval '00:31:00'";   #01:01:00 for 1hr LTA
my $fth = $connect->prepare($ti1);
$fth->execute();
my $pct = $fth->fetchrow_array();
  #my $pct = "2012-05-03 14:40:40"; #v#
  #my $end = "2012-05-03 15:30:00"; #v#


# This will be used to set the next query time (5seconds from the latest "pct")
my $statement = "select timestamp '$pct' + interval '5 seconds'"; 
my $nh = $connect->prepare($statement);
$nh->execute();
my $nt = $nh->fetchrow_array();
print "$nt\n";

$lastdrop = $nt;   #there's no data before this first call, so don't allow a trigger
$wasdrop = 1;

#Push a few "dummy" numbers into arrays, to avoid division by 0 errors
push(@ts,1);
push(@ts,1);
push(@tsnf,1);
push(@tsnf,1);
push(@tt,$pct);
push(@tt,$pct);

# These counters and flags are used to determine whether a "followup" email is needed
my $count_recent = 999;
my $wait = 999;
my $ff = 0;


## Enter the loop
print "Entering infinite loop.\n\n";
my $trigable = 1;  #able to trigger when not in a trigger, and not in a dropout
my $ret = 1;
while ( $ret == 1 )
{

  @tdl = gmtime(time);	

  if ($hr != $tdl[2])   #Start of a new hour = write things to log
  {
     &layt_check;  # Note the hour's average and max latency
     $hr = $tdl[2];     #Store "hr" for the next hour.
  }

  # Start a new day's log at 12:00 GMT (5am MT)
  #  Also require that previous log day and hour, @td, not both match current time
  #  (This prevents a log from being restarted twice in one day,
  #    even if system as whole reboots during 12:00 hour)

  if ($tdl[2] == 12 && ($tdl[2] != $td[2] || $tdl[3] != $td[3])) 
  {

     # Move the current "log_write" to a separate directory
     open LOGFILE, $log_write or die "error loading previous log";
     $first_line = <LOGFILE>; 
     close LOGFILE;
     chomp($first_line);
     $log_store = "./Logs/Tedect_$first_line.txt";
     $result = `mv $log_write $log_store`;


     &startlog;

     # Generate a status report based on previous day's logs
     $today = "$year[0]_$month[0]_$td[3]";
     TedStatus::status_generate($today);
     TedStatus::email_status($today);

  }

 ## $sqlt will be what server thinks "now" is.
#  $tquer = "select CURRENT_TIMESTAMP + interval '7 hours';";
#  $tqh = $connect->prepare($tquer);  #time query handle (tqh)
  $tqh->execute();
  $sqlt = $tqh->fetchrow_array();





  $tich_nq->execute($nt,$sqlt);   #Get the number of tweets in this interval
  $ticb = $tich_nq->fetchrow_array();
   
  if ($ticb >= 5){  #There are enough tweets, proceed with queries
    $t1 = [gettimeofday]; 


   
    #query will ask for # of tweets between $pct(previous) and $nt(next)
    $tich->execute($pct,$nt);   #Get the number of tweets in this interval
    $tic = $tich->fetchrow_array();
    $tic_all = $tic;
    if($verb)
    {
      print LOGFILE "\nNew bin queried at $sqlt :: bin $nt :  $tic\n";
      print "\nNew bin queried at $sqlt :: bin $nt :  $tic\n";
    }

#######################

#This requires word count
        $tich2->execute($pct,$nt);
        # BIND TABLE COLUMNS TO VARIABLES
        $tich2->bind_columns(\$text);
        
        #LOOP THROUGH RESULTS
         $tic = 0;
         $words = 0;
         while($tich2->fetch()) 
         {
            $words = scalar(split(/\s+/, $text));
            if ($words < $wcut)
            {
               $tic += 1;
            }
         }
    




########################

    #same thing, but unfiltered tweets
    $tich_nq->execute($pct,$nt);   #Get the number of tweets in this interval
    $ticnf = $tich_nq->fetchrow_array();
    print LOGFILE "WCnted: $tic  Unfiltr: $ticnf\n";



 #  at 5second bins:
 #    1min = 12 bins
 #    30min = 360 bins
 #    60min = 720 bins
    unshift(@ts,$tic);
    unshift(@tt,$nt);
    unshift(@tsnf,$ticnf);

    
    if($recording == 1)
    {  print TSH "$tic_all|$nt\n"; }
    
    # We want to keep only what's necessary in RAM / buffer
    #while (scalar(@ts) > 374)  #734 for 1hr LTA
    while (scalar(@ts) > $lsta*12 + $llta*12 + 2)  # 12 5-second-bins per min.
    {
       # "pop" removes the last element
       pop(@ts);  # Time-series, number of tweets in the bins
       pop(@tt);  # Timestamp series
       pop(@tsnf); # Time-series, no filter
    }

    #update $pct to now 
    $pct = $nt;
     #if( $pct =~ $end) #v#
     #{print "reached the end\n"; exit; } #v#

    # This is used for benchmark timing
    $et = tv_interval($t1);
    
    
   ## Finally, the critical math. Compare the LTA and STA
    if(scalar(@ts) > $lsta*12 + $llta*12){  
      $chrf= &sscfunc;   #Do the math, would it trigger?


###############
      ### Check for low "almost zero" cases of dropouts
      $z_check = eval join '+', @tsnf[0..59];
      if($z_check < 2 && $wasdrop == 0)
      {
         if($isdrop == 0)
         {
            $z_start = $tt[59]; 
            print LOGFILE "\nz_start: $z_start\n";
         }
         $isdrop = 1;
         $wasdrop = 1;
         $trigable = 0;
      }
      elsif($isdrop == 1 && $z_check > 2)   #z_check > 5
      {                   #was in a dropout, now good again
         $isdrop = 0;
         $z_end = $nt;
         print LOGFILE "\nz_end: $z_end\n";
         $lastdrop = $nt;   # mark the end of the last dropout / "zeroes"
      }

      # Once the time of previous dropout has rolled through the array,
      #   we can turn the system back on.
      #if($lastdrop =~ $tt[371] && $isdrop == 0)  #731 for 1hr LTA
      if($lastdrop =~ $tt[($lsta*12)+($llta*12)-1] && $isdrop == 0)  
      {
        $wasdrop = 0;
        print LOGFILE "\n$lastdrop lastdrop\n";
        print LOGFILE "$tt[($lsta*12)+($llta*12) -1]\n";
        print LOGFILE "wasdrop back off\n";
      } 
    }
################
        

    if ($trigable == 1 && $chrf >=1 && $wasdrop == 0){

       $trig_time = $nt;
       $trigable = 0;
       $count_recent = 0;
       $ff = 0;
       $mxstc = $stc;

          print LOGFILE "New Trigger!! Trig time: $trig_time,  Computer time: $sqlt. chrf: $chrf.\n"; 
          print LOGFILE "@ts";
          print LOGFILE "Attempting to email...\n\n";
       
       &body_generate;
       $date_f = &date_format($nt);
       TedEmail::email_all($date_f,$topgeo,$totnum); #v#
       TedTweet::tweetout($date_f,$blat,$blon,$topgeo,$totnum); #v#
       #TedSMS::textSMS($date_f);


    }
    # The "moderate" interest followup. 
    elsif( ($chrf >= 1 || $stc >= 50) && $ff == 0 )
    { 
       if ($count_recent <= 59)  #last 5 min
       {
          $ff = 1; #activate followup flag
          $mxstc = $stc;
          print "\n\n---Flagging for followup...---\n\n";
       }
    }
    elsif($chrf < 0.25 && $trigable == 0 && $wasdrop == 0 && $count_recent > 60){   #turn it back on
       $trigable = 1; #re-activate triggerable
       $mxstc = 9999; #set it arbitrarily high for normal periods
    }


    if($stc > $mxstc)
    {
       $mxstc = $stc;  #it has raised since last check
    }
    elsif( $stc < ($mxstc*0.8) && $ff == 1 )
    # it has definitely peaked, *and* a folloup flag has tripped
    {
       $ff3 = $ff;
       $ff = 2;
       $wait = 0;
        print "\n\n---It has peaked, waiting at least 1 min.---\n\n";
    }

    if ($wait == 12) #1 min has passed
    {
print "\n\n--FOLLOWING, 1 min past peak--\n\n";
#       TedFollow::followup($trig_time,$topgeo,$geolistref);
    }

    if($count_recent == 60 && $ff ==1)
    #It got to 5min, hasn't peaked, but a followup flag has tripped
    {
print "--FOLLOWING, 5 min past trigger--\n\n";
#       TedFollow::followup($trig_time,$topgeo,$geolistref);
       $ff = 2;
       $wait = 999;
    }
    

    $count_recent++;
    $wait++;

    #Define $nt
    $ti1 = "select timestamp '$pct' + interval '5 seconds'";
    $nh = $connect->prepare($ti1);
    $nh->execute();
    $nt = $nh->fetchrow_array();

  }



  else {      # We weren't ready to call the the next bin. Wait.
    if($verb)
    {
       print LOGFILE ".";
    }
    sleep 1;   #not ready to query, wait 1 second and try again
  } 

} 



##################################
# &sscfunc
# 
#  Sums the bins and averages to make STA and LTA
#  Use characteristic function to define a trigger
#################################
sub sscfunc {
  $stc = eval join '+', @ts[0..11];

#  $sta = $stc / 12;
  $sta = $stc;

  $ltc = eval join '+', @ts[12..371];  #731 for 1hr LTA
#  $lta = $ltc / 720;
  $lta = $ltc / 30;
  if ($lta != 0)
  {  $chrf = $sta/($mm*$lta+$CC); }
  else
  {  $chrf = 0.0999; }
  
  if($verb)
  {
     print LOGFILE "Char-func: $sqlt|$nt|$et|$sta|$lta|$chrf|$trigable|$tic\n";
  }
  $chrf = $sta/($mm*$lta+$CC);
}






#################################
# &body_generate
#
# 
################################

sub body_generate {
   my %top3;
   $b1 = [gettimeofday]; 
   open BODY, ">email.txt" or die "PERL could not create email text\n";

   ### setup times to display in map
   $statement = "select timestamp '$nt' - interval '4 minutes'"; 
   $nh = $connect->prepare($statement);
   $nh->execute();
   $t1 = $nh->fetchrow_array();
   @t1sp = split(' ',$t1,' ');
   @t1sp1 = split('-',$t1sp[0]);
   @t1sp2 = split(':',$t1sp[1]);
   @t1sec = split('\.',$t1sp2[2]);
   $tdt1 = "$t1sp1[0]/$t1sp1[1]/$t1sp1[2]";
   $ttm1 = "$t1sp2[0]:$t1sp2[1]:$t1sec[0]";
  
   $statement = "select timestamp '$nt' - interval '1 minutes'"; 
   $nh = $connect->prepare($statement);
   $nh->execute();
   $t2 = $nh->fetchrow_array();
   @t2sp = split(' ',$t2);
   @t2sp1 = split('-',$t2sp[0]);
   @t2sp2 = split(':',$t2sp[1]);
   @t2sec = split('\.',$t2sp2[2]);
   $tdt2 = "$t2sp1[0]/$t2sp1[1]/$t2sp1[2]";
   $ttm2 = "$t2sp2[0]:$t2sp2[1]:$t2sec[0]";

   $statement = "select timestamp '$nt' + interval '10 minutes'";
   $nh = $connect->prepare($statement);
   $nh->execute();
   $t3 = $nh->fetchrow_array();
   @t3sp = split(' ',$t3);
   @t3sp1 = split('-',$t3sp[0]);
   @t3sp2 = split(':',$t3sp[1]);
   @t3sec = split('\.',$t3sp2[2]);
   $tdt3 = "$t3sp1[0]/$t3sp1[1]/$t3sp1[2]";
   $ttm3 = "$t3sp2[0]:$t3sp2[1]:$t3sec[0]";

    ($rawref,$laloref,$geolistref) = TedTools::get_tweets($t2,$nt,$connect,$filt,$wcut);
    my $top3 = TedTools::raw_comm(@$rawref);
    my $revgeoloc = TedTools::rev_code(@$laloref);
    ($topgeo, $totnum) = TedTools::geo_comm(@$geolistref);
    print "$topgeo is topgeo.\n";
    print LOGFILE "TopGEOS: $topgeo\n";
   
    print BODY "Twitter event detection\n";
    print BODY "NOT AN OFFICIAL USGS ALERT\n";
    print BODY "NOT SEISMICALLY VERIFIED\n";
    print BODY "\n";
    print BODY "-------------\n";
    print BODY "Detection Time:\n";
    print BODY "-------------\n\n";
    $date_f = &date_format($nt);
    print BODY "$date_f\n";
    print BODY "\n";
    print BODY "-------------\n";
    print BODY "Possibly felt in:\n";
    print BODY "-------------\n\n";
    my $word;
    my $freq;
    my $key;
    my $value;
    my $lhrefs;
    $blat = 999;
    $blon = 999;

    if($topgeo !~ 'None')
    {
       #print BODY "$topgeo $totnum\n";
       my $best = TedTools::geo_code($topgeo); #reference to an array of references to hashes (yuck!)
       print BODY "$$best{'geos'} $totnum\n";
       if($$best{'qual'} >= 25)
       {
          $blat = sprintf '%.3f', $$best{'lat'};
          $blon = sprintf '%.3f', $$best{'lon'};
          print BODY "$blat, $blon\n\n";
       }
       print BODY "City: $$best{'l3'}\n";
       print BODY "Level2: $$best{'l2'}\n";
       print BODY "Level1: $$best{'l1'}\n";
       print BODY "Country: $$best{'l0'}\n\n";
       
#        else
#        {
#           $topgeo = 'None';
#           $blat = "geolocation not possible";
#           $blon = "";
#           print BODY "geolocation not possible\n\n";
#        }
    }
    else
    {
       print BODY "Not enough for a good estimate.\n\n";
    }

    foreach $word (sort { $$top3{$b} <=> $$top3{$a} } keys %$top3)
    {
       $freq = $$top3{$word};
       if($freq >= 2)
       {
           print BODY "$word  $freq\n";
       }
    }

    print BODY "\n";
    print BODY "-------------\n";
    print BODY "Triggering Tweets\n";
    print BODY "-------------\n\n";

    #open(TRTWEETS, "./tweets_used.tmp");
    open TRTW, "tweets_used.tmp" or die "tweets file not generated\n";
    my @tmp = <TRTW>;
    my $txt = join '', @tmp;
    print BODY $txt;

    print BODY "-------------\n";
    print BODY "Other Tweets\n";
    print BODY "-------------\n\n";

    open(OTWEETS, "./tweets_other.tmp");
    my @tmp = <OTWEETS>;
    my $txt = join '', @tmp;
    print BODY $txt;
    close OTWEETS;
#d    my $query = "select twitter_id, date_created, twitter_date, text, to_be_geo_located, coalesce(st_y(status.location),999) as lat, st_x(status.location) as lon, coalesce(location_string,'No location string'), location_quality, location_type from status where twitter_date > '$t2' and twitter_date < '$nt' order by date_created desc";
#d    my $query_handle = $connect->prepare($query);
#d    
#d    # EXECUTE THE QUERY
#d    $query_handle->execute();
#d    
#d    # BIND TABLE COLUMNS TO VARIABLES
#d    $query_handle->bind_columns(\$twitter_id, \$date_created, \$twitter_date, \$text, \$to_be_geo_located,\$lat,\$lon,\$loc_string,\$loc_qual,\$location_type);
#d    
#d    #LOOP THROUGH RESULTS
#d     while($query_handle->fetch()) {
#d        $mlat = 999;
#d        $mlon = 999;
#d        $mstr = '';
#d
#d        # Determine where the geolocation came from, 
#d        #   and whether it contributed to region estimate
#d        $GG = 0;
#d        if ($location_type =~ /GeoLocation/ && $lat != 999)
#d        {
#d           $type = "(A)";
#d           $mlat = sprintf '%.3f', $lat;
#d           $mlon = sprintf '%.3f', $lon;
#d           $GG = 1;
#d        }
#d        elsif ($location_type =~ /Place/ && $lat != 999)
#d        {
#d           $type = "(B)";
#d           $mlat = sprintf '%.3f', $lat;
#d           $mlon = sprintf '%.3f', $lon;
#d           $GG = 1;
#d        }
#d        elsif ($location_type =~ /Location-String/)
#d        {
#d           if($loc_string =~ /(T:|iPhone:|^\s?)\s?(\-?\d{1,3}\.\d{3,9})\s?,\s?(\-?\d{1,3}\.\d{3,9})/)
#d           {
#d              $mlat = $2;
#d              $mlon = $3;
#d              $type = "(C)";
#d              $GG = 1;
#d           }
#d           else
#d           {
#d          #    $loc_string =~ tr/A-Za-z/ /cs;
#d              $loc_string =~ tr/\.\,\[\]\(\)-/ /s;
#d              for $lhrefs(@$geoloc)
#d              {
#d                 if ( $loc_string eq $$lhrefs{'loc_string'} )
#d                 {
#d                    if($$lhrefs{'qual'} >= 25)
#d                    {
#d                       $mlat = sprintf '%.3f', $$lhrefs{'lat'};
#d                       $mlon = sprintf '%.3f', $$lhrefs{'lon'};
#d                       if(exists($$lhrefs{'city')) 
#d                       {
#d                          $mstr = $mstr.$$lhrefs{'city'}.', ';
#d                          $GG = 1;
#d                       }
#d                       if(exists($$lhrefs{'state')) 
#d                       {
#d                          $mstr = $mstr.$$lhrefs{'state'}.', ';
#d                          $GG = 1;
#d                       }
#d                       if(exists($$lhrefs{'country')) 
#d                       {
#d                          $mstr = $mstr.$$lhrefs{'country'};
#d                       }
#d               
#d                       $type = "(C)";
#d                       last;
#d                    }
#d                 }
#d              }
#d           }
#d        }
#d
#d        # Test text for whether it would've counted for trigger
#d        $TT = 1;
#d        $words = scalar(split(/\s+/, $text));
#d        if ($words >= $wcut)
#d        {
#d           $TT = 0; #It did not pass the word count req.
#d        }
#d
#d        if($TT==1) 
#d        {
#d           foreach $wfilt(@filt2)
#d           {
#d               if($text =~ /$wfilt/)
#d               {
#d                   $TT = 0; #It did not pass the filters
#d               }
#d           }
#d        }
#d        ## Finished testing. Finally print the tweet
#d       
#d        $date_f = &date_format($twitter_date);
#d        if($TT == 1 && $GG ==1)
#d          {print BODY "$date_f TG\n";}
#d        elsif($TT==1 && $GG==0)
#d          {print BODY "$date_f T\n";}
#d        else
#d          {print BODY "$date_f\n";}
#d     
#d 
#d        print BODY "UL: $loc_string\n";
#d        if($mlat != 999)
#d        {
#d            print BODY "GEO:  $mlat, $mlon  $type\n";
#d        }
#d        else
#d        {
#d            print BODY "GEO: no geolocation\n";
#d        }
#d        
#d
#d
#d
#d
#d        print BODY "$text\n\n";
#d        &record;
#d     } 
    print BODY "\n";
    print BODY "-------------\n";
    print BODY "Recent earthquakes\n";
    print BODY "-------------\n\n";
    $date_f = &date_format($nt);
    print BODY "Twitter Detection:\n$date_f\n";
    if($topgeo !~ 'None')
    {
        print BODY "$topgeo\n";
        print BODY "$blat, $blon\n\n";
    }
    else
    {
        print BODY "no region estimate\n\n";
    }
    print BODY "USGS: http://on.doi.gov/2IZXwx\n";
    print BODY "EMSC: http://bit.ly/gGYick\n";
    print BODY "U Chile: http://www.sismologia.cl\n";
    print BODY "Japan: http://bit.ly/gE1CwL\n";
    print BODY "Indonesia: http://bit.ly/AiQfCl\n";
    print BODY "New Zealand: http://bit.ly/yWaMsK\n";

    print BODY "\n";
    print BODY "-------------\n";
    print BODY "Tweet Map\n";
    print BODY "-------------\n\n";

    print BODY "Tweets 4 min before and 10 min after detection\n";
    print BODY "http://geohazards.usgs.gov/station/historical_tweetsGE.php?begindt=$tdt1&enddt=$tdt3&begintm=$ttm1&endtm=$ttm3&keywd=&loc_qual=between%200%20and%20100\n\n";
    print BODY "-------------\n";
    print BODY "Background:\n";
    print BODY "-------------\n\n";
   
    print BODY "This possible earthquake detection is based solely on Twitter data and has not been seismically verified. We use a sensitive trigger so expect some false triggers. The first tweets listed generally precede tweets about the event and are from random locations around the world. False triggers can usually be identified by scanning the the tweet text to see if it is consistent with what you would expect after an earthquake. False triggers often contain repeat text or tweets that all come from random locations around the globe.\n\n";
    print BODY "Detection Time:\nThe detection time is usually 1 to 5 minutes after earthquake origin time. Earthquakes are generally detected before seismically derived solutions are publicly available.\n\n";
    print BODY "Location Estimate:\nThe location estimate is our best estimate of city that produced the most tweets. This is followed by the most common words with counts in the user's location string.\n\n";
    print BODY "Tweets:\nFor each tweet we may list:\n";
    print BODY "1) UTC time that the tweet was sent\n";
    print BODY "2) User provided location string (UL:)\n";
    print BODY "3) Best guess of user coordinates (GEO:)\n";
    print BODY "4) Geolocation string returned from Yahoo (GEOS:)\n";
    print BODY "5) Tweet text (TXT:)\n";
    print BODY "All tweets shown starting one minute prior to detection time\n\n";
    print BODY "Location details:\n";
    print BODY "UL: Corresponds to the user supplied free-format text string. This can be inaccurate because users often enter \"clever\" locations such as \"on the earth\". Additionally, they may not be in their home city when they sent the tweet. Some twitter clients insert a decimal latitude and longitude in the location string.\n\n";
     print BODY "GEO: Corresponds to our best estimate of the latitude and longitude.\n";
     print BODY "The source of the geolocation is indicated by a letter following the latitude and longitude:\n";
     print BODY "(A) a precise latitude and longitude, likely GPS based.\n";
     print BODY "(B) A Twitter \"place\" location, usually accurate to the city level.\n";
     print BODY "(C) a geolocation of the users free-format location string (UL). This is only as good as what the user specifies in the free-format location string and what the Yahoo geocode service returns. Some locations may not have been geocoded at the time the alert was sent.\n";
    print BODY "\n\n";
    print BODY "-------------\n";
    print BODY "System information:\n\n";

    $date_f = &date_format($nt);
    print BODY "Detection Time:\n$date_f\n";

    $tqh->execute();
    $sqlt = $tqh->fetchrow_array();
    $date_f = &date_format($sqlt);
    print BODY "Alert Time: \n$date_f\n\n";

    print BODY "Chrf = $chrf\n";
    print BODY "LTA(30min) = $lta tweets/min\n";
    print BODY "STA(1 min) = $sta tweets/min\n";
    print BODY "mm = $mm, CC = $CC\n";
    print BODY "Filtering out tweets with numbers (0-9),'http','\@',' RT ','predict','song', 'drill', and 'MundosOpuestos'.\n";
    print BODY "Only counting tweets with 7 words or less.\n\n";

    print BODY "version 1.1.2\n";

    close BODY;
    $bench = tv_interval($b1);
    print "Email took: $bench seconds\n";
}
 

   

###########################
# date_format
#
#
###########################    
sub date_format {
  @datestamp = split(' ',$_[0]);
  $datestamp[0] =~ s/\-/\//g;
  @times = split(':',$datestamp[1]);
  $times[2] = sprintf '%.2d', $times[2]; 
  $datestamp[1] = "$times[0]:$times[1]:$times[2]";
  $date_f = "$datestamp[0] $datestamp[1]";
}
  

###########################
# layt_check 
#
#
###########################    
sub layt_check {
     
     my $hour1 = $sqlt;
     my $h2 = "select timestamp '$hour1' - interval '01:00:00'";
     my $hh2 = $connect->prepare($h2);
     $hh2->execute();
     my $hour2 = $hh2->fetchrow_array();

     my $laytq = "select avg((extract(epoch from date_created) - extract(epoch from twitter_date))) as avlayt, max(extract(epoch from Date_created) - extract(epoch from twitter_date)) as maxlayt, count(twitter_id) from status where twitter_date > '$hour2' and twitter_date < '$hour1' and text !~ '$filt'";

     my $layth = $connect->prepare($laytq);
     $layth->execute();
     $layth->bind_columns(\$avlayt, \$maxlayt,\$tweet_count);
     $layth->fetch();
     
     print LOGFILE "\navlatency: $avlayt\n";
     print LOGFILE "\nmaxlatency: $maxlayt\n";
     print LOGFILE "\ntweet_count: $tweet_count\n";

}



###########################
# startlog
#
#
###########################    
sub startlog {
     #my $logname = "./Logs/TEDect_$year[0]_$month[0]_$td[3]_$td[2]_$td[1]_$td[0].txt";

     # get current timestamp for new logfile
     @td = gmtime(time);	
       # Returns: ss mm hh DD MM YYYY day_in_year day_of_week daylight_sav
     @year = 1900 + $td[5];
     @month = 1 + $td[4];
     $hr = $td[2];

     # "log_write" is always the current buffer log-file.
     # This should always start with a timestamp on first line, for file naming purposes
     open LOGFILE, ">$log_write" or die "PERL could not create logfile\n";
     $| = 1;
     print LOGFILE "$year[0]_$month[0]_$td[3]_$td[2]_$td[1]_$td[0]\n";
     print LOGFILE "Starting new log.\n\n";
     print LOGFILE "mm used: $mm\n";
     print LOGFILE "CC used: $CC\n";
     print LOGFILE "This log will display when a query is performed, timeseries, and char. function.\n";
     print LOGFILE "ex: Char-func: computer_time | bin_end_time | timing_benchmark | sta | lta | chrf | trig_state | #_last_bin\n";
}







exit 0;

