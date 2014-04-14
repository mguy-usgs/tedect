package TedTweet;
use Net::Twitter::Lite;

###############################################################################
#  This software is in the public domain because it contains materials
#  that originally came from the United States Geological Survey, 
#  an agency of the United States Department of Interior. For more 
#  information, see the official USGS copyright policy at 
#  http://www.usgs.gov/visual-id/credit_usgs.html#copyright
###############################################################################

###############################################################################
# tweetout:
#  notes: 
###############################################################################
sub tweetout
{
   my $datetime = shift;
   my $tlat = shift;
   my $tlon = shift;
   my $loc = shift;
   my $totnum = shift;
   my $return_value = 1;
   my $result;
   if( open IN, './up.ups' )  #External file with user names and pass
   {
         my $up;
         chomp($up =  <IN>);
         my @ups = split('\|',$up);
       
         my $nt = Net::Twitter::Lite->new(
           consumer_key        => "$ups[0]",
           consumer_secret     => "$ups[1]",
           access_token        => "$ups[2]",
           access_token_secret => "$ups[3]" 
         );
         
         if ($loc !~ 'None' && $tlat != 999)
         {
              $result = eval {$nt->update({status => "$loc $totnum\n$datetime", lat => $tlat, lon => $tlon})};
         }
         elsif($loc !~ 'None')
         {
              $result = eval {$nt->update({status => "$loc $totnum\n$datetime"})};
         }

         else
         {
              $result = eval {$nt->update("location undetermined\n$datetime")};
         }
         
         
         warn "$@\n" if $@;
          print "Tweet sent\n";
   }
   else 
   {
      warn "no ups. No tweet sent\n";
   }
}
1;
