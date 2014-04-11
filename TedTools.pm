package TedTools;

use Encode;
use URI;
use LWP::UserAgent;
use utf8;
use Text::Unidecode;
use Unicode::Normalize;
use Net::OAuth;
use Digest::SHA::PurePerl qw(sha1 hmac_sha1);
use Digest::HMAC_SHA1;
#use Digest::SHA::PurePerl qw(sha1 sha1_hex sha1_base64 ...);
#use Digest;
#use Digest::SHA;
#use Digest::HMAC_SHA1;

###############################################################################
## get_tweets:
##  parameters: 
##     $t2      time to start the query
##     $nt      time to end the query
##     $connect handle for SQL database credentials
##     $filt    word filter list
##     $wcut    maximum number of words in the tweet for filter
##  return: 
##     $rawbatch  array reference of raw, user-defined location strings
##     $lalo      array reference of lat,lons from Twitter Place, Geolocation, 
##                  or those with a "UT:" or "iPhone:" listing.
##  notes: 
################################################################################
sub get_tweets
{
   my $return_value = 1;
      #Read in the arguments
      my $t2 = shift;
      my $nt = shift;
      my $connect = shift;      
      my $filt = shift;
      my $wcut = shift;


      # Declare variables
      #   Not every variable needs to be declared at beginning, 
      #   but since these are inside of a loop, it'll run faster
      #   if they're declared once, at the beginning.
      my (@this_text, $word, @all_text, %rawfreq, %top3raw, @geobatch, @rawbatch, @txts, $wds, $lat, $lon, $loc_type, $lalo, @lalos, $text, $passfilt, $wfilt, $type, @geolist, $geo_u);
      my $ii = 0;

      $filt =~ tr/)(//d; 
      my @filts = split(/\|/,$filt);
      
      open TMP, '>tweets_used.tmp' or die ' could not open tweets.tmp';
      open TMP2, '>tweets_other.tmp' or die ' could not open tweets_other.tmp';


      my $loc_query = "select twitter_id, date_created, twitter_date, text, to_be_geo_located, coalesce(st_y(status.location),999) as lat, st_x(status.location) as lon, coalesce(location_string,'None'), location_quality, location_type from status where twitter_date > '$t2' and twitter_date < '$nt' order by date_created desc";
      my $loc_query_handle = $connect->prepare($loc_query);
      # EXECUTE THE QUERY
      $loc_query_handle->execute();
      # BIND TABLE COLUMNS TO VARIABLES
      $loc_query_handle->bind_columns(\$twitter_id, \$date_created, \$twitter_date, \$text, \$to_be_geo_located,\$lat,\$lon,\$loc_string,\$loc_qual,\$loc_type);

print "t2 = $t2\n";
print "nt = $nt\n";

      #LOOP THROUGH RESULTS
      while($loc_query_handle->fetch()) 
      {
         #first make sure we've cleared data from the last tweet
         $geoloc_ref = '';
         $type = '';

        #$loc_string = decode_utf8( $loc_string );
        #$loc_string = unidecode($loc_string);
        #$text = decode_utf8( $text );
        #$text = unidecode($text);

        #First test whether it would pass the filter
        $passfilt=1;
        foreach $wfilt(@filts)
        {
          if($text =~ /($wfilt)/i)
            {$passfilt=0;}
        }
      
        #then test whether there's not too many words
        $wds = scalar(split(/\s+/, $text)); 
           # Does it count towards the trigger? (T)
        if ($wds < $wcut && $passfilt==1) #then Geocode it!!
        {
           push(@txts,$text);
print "passing: $loc_string\n";
print "$text\n";

           if($loc_string !~ /None/ || $loc_type =~ /GeoLocation/ || $loc_type =~ /Place/)
           {
               #Geocode by whatever means appropriate
               #    Whether that be geo_code, rev_code, extract iPhone:, etc...
               if($loc_type =~ /GeoLocation/ )
               {
                   $lalo = "$lat, $lon";
                   push(@lalos,$lalo);  #collection of raw lat/lons
                   $geoloc_ref = &rev_code($lalo);
                   $type = "(A)";
               } 
               elsif($loc_type =~ /Place/)
               {
                   $lalo = "$lat, $lon";
                   push(@lalos,$lalo);  #collection of raw lat/lons
                   $geoloc_ref = &rev_code($lalo);
                   $type = "(B)";
               } 
               elsif($loc_type =~ /Location-String/)
               {
                  $type = "(C)";
                  if($loc_string =~ /(T:|iPhone:|^\s?)\s?(\-?\d{1,3}\.\d{3,9})\s?,\s?(\-?\d{1,3}\.\d{3,9})/)
                  {
                     print "--- Location: $loc_string ---\n";
                     print "$2, $3\n\n";
                     $lalo = "$2, $3";
                     push(@lalos,$lalo);
                     $geoloc_ref = &rev_code($lalo);
                  }
                  else
                  { 
                      push(@rawbatch,$loc_string); #collection of raw strings
                      $geoloc_ref = &geo_code($loc_string);
                  }
               }

               #whatever means it took to geocode, now we have it
               my %gc = %$geoloc_ref; 

               #Does this tweet count for the region estimate?
               my $qq = $gc{'qual'};
               if( ($qq>=10 && $qq<=65) || ($qq>=90) ) 
               {
                   #push(@geolist,$geoloc_ref);   #geolist is the one we use for Region estimate
                   push(@geolist,{%gc});   #geolist is the one we use for Region estimate
                   $geo_u = 1;
               }
               else 
                  {$geo_u = 0;}

               #Now we have the geolocation, print the tweet   
               $date_f = &date_format($twitter_date);
               print TMP "$date_f\n";
               print TMP "UL: $loc_string\n";
               if ($geo_u==1)
               {
                   $mlat = sprintf '%.3f', $$geoloc_ref{'lat'};
                   $mlon = sprintf '%.3f', $$geoloc_ref{'lon'};
                   print TMP "GEO: $mlat, $mlon $type\n";
                   print TMP "GEOS: $gc{'l3'}, $gc{'l2'}, $gc{'l1'}, $gc{'l0'}\n"; 
               }
               else
               {
                   print TMP "GEO: (none, not used)\n";
               }
               print TMP "TXT: $text\n\n";
           }
           else
           {
                #used in trig, not in geo
               #print tweet
                $date_f = &date_format($twitter_date);
                print TMP "$date_f $ttgg\n";
                print TMP "UL: No location string\n";
                print TMP "GEO: None\n";
                print TMP "TXT: $text\n\n";
           }
        }
        else
        {
             #N# It wasn't used in the trigger or geocoding, print that tweet
            $date_f = &date_format($twitter_date);
            print TMP2 "$date_f $ttgg\n";
            if($loc_string !~ /None/)
            {
                print TMP2 "UL: $loc_string\n";
            }
            else
              {print TMP2 "UL: No location string\n";}
            
          #   if($lat !~ /999/ && $loc_type =~ /GeoLocation/)
          #     {print TMP2 "GEO: $lat, $lon (A)\n";}
          #   elsif($lat !~ /999/ && $loc_type =~ /Place/)
          #     {print TMP2 "GEO: $lat, $lon (B)\n";}
          #   else
          #     {print TMP2 "GEO: None\n";}
            print TMP2 "TXT: $text\n\n"
        }
      }
   close TMP;
   close TMP2;
   return(\@rawbatch,\@lalos,\@geolist);
#N# change what it returns
#N# change how its called from tedect.pl
#N# make sure geolist is properly passed to geo_comm
}


###############################################################################
## raw_comm:
##  parameters: 
##     @rawbatch   array of user strings
##  return: 
##     $%top3raw  hash reference, top 3 words from user defined strings
##  notes: 
################################################################################
sub raw_comm{
   my @raws = @_; #read in array of all inputs
   my @this_text;
   my $word;
   my @all_text;
   my %rawfreq;
   my %top3raw;
   my $ii = 0;
   my $loc_string;

   foreach $loc_string(@raws)
   {

         # trade everything thats *not*(c) a letter for a space
         $loc_string = decode_utf8( $loc_string );
         $loc_string = unidecode($loc_string);
         $loc_string =~ tr/A-Za-z'/ /cs; 

         #break on each space, make lower case
         foreach $word (split(' ', lc $loc_string))
         {
             #if there is actual text (not a whitespace char) 
             if($word =~ /\w/)   
             {                     
                # add it to array of all words           
              ####   push(@all_text, lc $word)  
                $rawfreq{lc $word}++;
             }
        
         }
      }
   
     #order by highest fr.
     foreach $word (sort { $rawfreq{$b} <=> $rawfreq{$a} } keys %rawfreq) 
     {
          print "$word $rawfreq{$word}\n";
          if($ii < 3 && length($word)>=3 && $word!~m/none/ && $word!~m/the/)
          {
             $top3raw{$word} = $rawfreq{$word};
             $ii++;
          }
     }

     return(\%top3raw);

}


###############################################################################
## geo_code:
##  parameters: 
##     @batch   array of user strings
##  return: 
##     /@locs   reference to array of hashes (this is getting rediculous!),
##               hash contains user string and results from geocoder
##  notes: 
################################################################################
sub geo_code
{

    my @batch = @_;
 
#    my $url = "http://query.yahooapis.com/v1/yql";
    my $url = "http://yboss.yahooapis.com/ysearch/news,web,images";  

    my $uri = URI->new('http://query.yahooapis.com/v1/public/yql');
    my $ua = LWP::UserAgent->new;
    $ua->timeout(10);
    my $response;
    my $data;
    my %loc = ();
    my @locs = ();
    my $location;
    my $wordcnt;
    my $geos = '';

    foreach $location(@batch)
    {
      $orig_str = $location;
     # $location = NFD($location);
          
      $location =~ tr/\.\,\[\]\(\)-/ /s;
      $location = decode_utf8( $location );

      %loc = ();
      my $geos = '';
      for (keys %loc)
      {
          delete $loc{$_};
      }
      
#       foreach $previous(geo {'loc_string'})
#       {
#          if($location == $previous)
#          {
#              $loc{loc_string} = $location;
             

    
# hardcoded... bad
#  
# v1.2 update: Request a secure key and token through yahoo.
    my $cc_key='yourYahooKeyHere';
    my $cc_secret='yourYahooPassCodeHere';
    my $request = Net::OAuth->request("request token")->new(  
            consumer_key => $cc_key,    
            consumer_secret => $cc_secret,   
            request_url => $url,   
            request_method => 'GET',   
            signature_method => 'HMAC-SHA1',  # key must be encrypted
            timestamp => time,   
            nonce => 'value',  
            callback => 'http://urlHere.example.com',   #meaningless
            extra_params => \%args   
            );  
    $request->sign;
    my $res = $ua->get($request->to_url);
    #print "RES: $res\n\n";
    # Once the key is signed and returned, This IP adress will be valid for making YQL calls
    #
    # (note: it might be possible to do this only once per trigger, or even only once per day...
    #    though this would require a more invasive overhaul of existing code)
    
         
      if($location !~ 'None')
      {
	 $q = "Select * from geo.placefinder where text=\"$location\"";
         $uri->query_form(
             #flags  => 'GT',
             #gflags => 'A',
	     #appid => 'test',
             q => $q,  #new-style, where you send the YQL query directly
         );
         print "$uri\n";
         $response = $ua->get($uri);
         $data =  $response->decoded_content;
         $data = decode_utf8( $data );
         $data = unidecode($data);
#      $location = decode_utf8( $location );
#      $location = unidecode($location);
#print "$data\n\n";
   
     if ($data =~ /<Result>(.*?)<\/Result/)
     { $data1 = $1;
         print "$orig_str --> $location\n";
         $loc{loc_string} = $location;
         if ($data1 =~ /<latitude>([^<]+)<\/latitude>/) 
         {  $loc{lat} = $1  };
         if ($data1 =~ /<longitude>([^<]+)<\/longitude>/) 
         {  $loc{lon} = $1  };
         if ($data1 =~ /<quality>([^<]+)<\/quality>/) 
         {  $loc{qual} = $1  };
         if ($data1 =~ /<city>([^<]+)<\/city>/ && $loc{qual}>=35)  #CITY
         {  
            $loc{l3} = $1; 
            $geos = $1.", ";
         }
         if ($data1 =~ /<county>([^<]+)<\/county>/ && $loc{qual}>=25)  #COUNTY
         {  
            $loc{l2} = $1; 
            if($geos !~ /\S/)
            {
                $geos = $geos.$1.", ";
            }
         }
         if ($data1 =~ /<state>([^<]+)<\/state>/ && $loc{qual}>=15)  #STATE
         {  
            $loc{l1} = $1; 
            $geos = $geos.$1.", ";
         }
         if ($data1 =~ /<country>([^<]+)<\/country>/ && $loc{qual}>=10)  #COUNTRY
         {  
            $loc{l0} = $1; 
            $geos = $geos.$1;
         }
         
         if($geos =~/\w/)  #does GEOS contain useful information?
         {
            $loc{geos} = $geos;
         }
         else
         {
            #if GEOS is still empty... not sure what it returned, but we don't want it 
            #   this is rare, but not impossible
            $loc{qual} = 0;
            $loc{lat} = 999;
            $loc{lon} = 999;
         }
         
         while(($keys,$values) = each( %loc ))
         {  
            print "$keys $values\n";
         }
         print "\n";
         push (@locs,{%loc});
#         print %loc;
       }
      }
      else
      {
         print "\nNot processing $location\n\n";
      }
 
    }
  return(\%loc);  #reference to hash
  #for multiple geocodes at once... needed to pass reference to an array of hashes
  #return(\@locs); 
}
   
###############################################################################
## rev_code:   reverse geocode
##  parameters: 
##     @batch   array of lat lons
##  return: 
##     /@locs   reference to array of hashes, 
##               hash contains user string and results from geocoder
##  notes: only difference is a flag thrown in the URL format. Could combine this
##     better with the original geo_code 
################################################################################
sub rev_code
{

    my @lalos = @_;
    #my $uri = URI->new('http://where.yahooapis.com/geocode');
    my $url = "http://yboss.yahooapis.com/ysearch/news,web,images";  
    my $uri = URI->new('http://query.yahooapis.com/v1/public/yql');

    my $ua = LWP::UserAgent->new;
    $ua->timeout(10);
    my $response;
    my $data;
    my %rev = ();
    my @revs = ();
    my $location;
    my $wordcnt;
    my $geos = '';

    foreach $location(@lalos)
    {

      $orig_str = $location;
      if($location !~ '999')
      {
            my $cc_key='yourKeyHere';
            my $cc_secret='yourCodeHere';
            my $request = Net::OAuth->request("request token")->new(  
                    consumer_key => $cc_key,    
                    consumer_secret => $cc_secret,   
                    request_url => $url,   
                    request_method => 'GET',   
                    signature_method => 'HMAC-SHA1',  
                    timestamp => time,   
                    nonce => 'data',  
                    callback => 'http://url.example.com',   #meaningless
                    extra_params => \%args   
                    );  
           $request->sign;
           my $res = $ua->get($request->to_url);
           #print "RES: $res\n\n";

	   $q = "Select * from geo.placefinder where text=\"$location\" and gflags= \"R\"";
           $uri->query_form(
               q => $q,  #new-style, where you send the YQL query directly
           );
           print "$uri\n";
           $response = $ua->get($uri);
         $data =  $response->decoded_content;
    
         
   
     if ($data =~ /<Result>(.*?)<\/Result/)
     { $data1 = $1;
	 $data = $data1;  #lazy juggling around
         $data = decode_utf8( $data );   ##better to decode each part, not whole data
         $data = unidecode($data);
	print "$data\n";
         %rev = ();
         $rev{loc_string} = $location;
         if ($data =~ /<latitude>([^<]+)<\/latitude>/) 
         {  $rev{lat} = $1  };
         if ($data =~ /<longitude>([^<]+)<\/longitude>/) 
         {  $rev{lon} = $1  };
         if ($data =~ /<Quality>([^<]+)<\/Quality>/) 
         {  $rev{qual} = $1  };
         if ($data =~ /<level3>([^<]+)<\/level3>/ && $rev{qual} >= 35)  #CITY
         {  
            $rev{l3} = $1; 
            $geos = $1.", ";
         }
         if ($data =~ /<level2>([^<]+)<\/level2>/ && $rev{qual} >= 25)  #COUNTY
         {  
            $rev{l2} = $1; 
            if($geos !~ /\S/)
            {
                $geos = $geos.$1.", ";
            }
         }
         if ($data =~ /<level1>([^<]+)<\/level1>/ && $rev{qual} >= 15)  #STATE
         {  
            $rev{l1} = $1; 
            $geos = $geos.$1.", ";
         }
         if ($data =~ /<level0>([^<]+)<\/level0>/ && $rev{qual} >= 10)  #COUNTRY
         {  
            $rev{l0} = $1; 
            $geos = $geos.$1;
         }
         $rev{geos} = $geos;



         
          while(($keys,$values) = each( %rev ))
          {  
             print "$keys $values\n";
          }
          print "\n";
         push (@revs,{%rev});
#         print %loc;
      }
      else
      {
         print "\nNot processing $location\n\n";
      }
 
    }
  }
  return(\%rev);
}




###############################################################################
## geo_comm:  now find region estimate 
##  parameters: 
##     @locs  intnded to pass it *both* geocoded and reverse geocoded arrays of hashes
##  return: 
##     $max   string, region estimate (most common geocode result), 
##     $ratio   string, number of hits out of the total 
################################################################################
sub geo_comm{

  my @locs = @_;
#  my @revs = shift;

  my $num = scalar(@locs);
  print "NUM COMBINDED: $num\n";
  my $str;
  my %l3_comm;  #city
  my %l2_comm;  #county
  my %l1_comm;  #state
  my %l0_comm;  #country

  for(my $ii=0; $ii<$num; $ii++)
  {
     if(exists($locs[$ii]{'l3'}))
     { 
       if(exists($locs[$ii]{'l1'}))
       {
           $str = $locs[$ii]{'l3'}.', '.$locs[$ii]{'l1'}.', '.$locs[$ii]{'l0'};
       }
       else
       {
           $str = $locs[$ii]{'l3'}.', '.$locs[$ii]{'l2'}.', '.$locs[$ii]{'l0'};
       }
       $l3_comm{$str}++;
     }

     if(exists($locs[$ii]{'l2'}))
     { 
       if(exists($locs[$ii]{'l1'}))
       {
           $str = $locs[$ii]{'l2'}.', '.$locs[$ii]{'l1'}.', '.$locs[$ii]{'l0'};
       }
       else
       {
           $str = $locs[$ii]{'l2'}.', '.$locs[$ii]{'l0'};
       }
       $l2_comm{$str}++;
     }

     if(exists($locs[$ii]{'l1'}))
     { 
       $str = $locs[$ii]{'l1'}.', '.$locs[$ii]{'l0'};
       $l1_comm{$str}++;
     }

     if(exists($locs[$ii]{'l0'}))
     { 
       $str = $locs[$ii]{'l0'};
       $l0_comm{$str}++;
     }

  }
print "\n\n\n";

  print "Starting at level3, city\n"; 
  my (@max) = sort { $l3_comm{$b} <=> $l3_comm{$a} } keys %l3_comm;
  print "$max[0] -- $l3_comm{$max[0]}\n";
  if($l3_comm{$max[0]} >= 3)
  {
     print "We have found it!\n";
     my $ratio = "($l3_comm{$max[0]}/$num)";
     return($max[0],$ratio);
  }

  print "working on level2, county\n"; 
  my (@max) = sort { $l2_comm{$b} <=> $l2_comm{$a} } keys %l2_comm;
  print "$max[0] -- $l2_comm{$max[0]}\n";
  if($l2_comm{$max[0]} >= 3)
  {
     print "We have found it!\n";
     my $ratio = "($l2_comm{$max[0]}/$num)";
     return($max[0],$ratio);
  }

  print "working on level1, state\n"; 
  my (@max) = sort { $l1_comm{$b} <=> $l1_comm{$a} } keys %l1_comm;
  print "$max[0] -- $l1_comm{$max[0]}\n";
  if($l1_comm{$max[0]} >= 3)
  {
     print "We have found it!\n";
     my $ratio = "($l1_comm{$max[0]}/$num)";
     return($max[0],$ratio);
  }

  print "working on level0, country\n"; 
  my (@max) = sort { $l0_comm{$b} <=> $l0_comm{$a} } keys %l0_comm;
  print "$max[0] -- $l0_comm{$max[0]}\n";
  if($l0_comm{$max[0]} >= 3)
  {
     print "We have found it!\n";
     my $ratio = "($l0_comm{$max[0]}/$num)";
     return($max[0],$ratio);
  }

  #No need to get fancy with if's and else's, if it hasn't returned by now, its "none"
  return "None";
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
  



1;

