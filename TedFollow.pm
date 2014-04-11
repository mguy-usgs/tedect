package TedFollow;


use TedGeo;
use TedTools;
use TedSeis;
use TedXML;
use Date::Parse qw( str2time );
use Date::Format qw( time2str) ;
use DBI;
use DBD::Pg;
use Encode;
use utf8;
use Text::Unidecode;




use threads;
use threads::shared;

my $waited : shared;
my $maxStc : shared;
my $numThreads : shared;

my $outputFolder        = "./output/"; #The output folder holds the log folder, and other tmp files
my $tweetaFile = $outputFolder."/tweeta.tmp";
my $textsFile = $outputFolder."/texts.tmp";
my $tsFile = $outputFolder."/ts.tmp";
	
sub setSPVerbose
{
	$spverbose = shift;
}

sub setSPMute
{
	$spmute = shift;
}
sub setSPDev
{
	$spdev = shift;
}


##########################################################################################
# Function: 		followStuff
# Description:  main calling subroutine for followup information 
#  (which includes waiting/checking for followup data available)
#
# @Param : $trigTime	--	Time trigger was detected
# @Param : $connect 	--	Connection handle to DBD::Pg TED sql database
#
##########################################################################################

sub followStuff{
        my $trigTime = shift;
	my $connect = shift;
	
	TedTools::log_msg("starting followStuff, $trigTime");


        my $peaked = 0;
	$waited = 0;
	$numThreads = 0;

	# DCB seismograms is currently the only use of threads here (geocoding uses them).
	#  I ran into many errors trying to multi-thread with shared/new SQL database handles
	#  Also complicated issues with sending to webserver since things finished at diff times
	#
	#   so decided that simple, old fashioned and linear was best.
        my $seis_thread = threads->create(\&seis, $trigTime, 1);
        $seis_thread->detach();

	#wait for peak, or 5 min, whichever comes first.
	#	this will continually test and write tweets
	&waitingGame($trigTime, $connect, $status);

	TedTools::log_msg("We've got it! We're past the peak, or 5min.");
	TedTools::log_msg("Waited = $waited, peaked = $peaked, maxStc = $maxStc");
	
	# Pass along the maxStc (max short term count, or tweets/min)
	TedXML::seteventtpm($maxStc);
	TedDB::seteventtpm($maxStc);
	
	TedDB::writeeventtpm(); # you know what i'm sayin'


	# Determine common words in text and loc strings
	my ($refCommLoc,$refCommText,$numTw) = TedTools::commonWords(0);
	TedXML::seteventcommonloc($refCommLoc);
	TedXML::seteventcommontext($refCommText);

	TedDB::seteventcommonloc($refCommLoc);
	TedDB::seteventcommontext($refCommText);

	# Generate and send followup tweet
	&followTweet;

	# Other than python stuff... we're done.
	#  Send it / ship it / close it
	#TedXML::writeeventtoXMLf();
	
	
	# Make the tweetgram
	&tweetGram($trigTime,$waited);

	# Make the heatmap
#	&heatMap($trigTime,$waited);

# DCB !! Last I tried heatMap, still have a prob with pyth packages...
#    matplotlib.basemap is a tricky install, and we prob lost it with Mike Sanders' latest updates
#    currently we get a seg-fault and python crashes when basemap tries to load...
	
	

	TedTools::log_msg("Finished with this stuff. Get back to work.")

}

sub waitingGame{
        my $trigTime = shift;
	my $connect = shift;
        my $status = shift;

        $waited = 0;   #measured in seconds
	$maxStc = 0;


	#will round down to nearest 10 seconds for TS starting
	my @splitStamp = split(' ',$trigTime);
	my @splitTime = split(':',$splitStamp[1]);
	my $seconds = $splitTime[2];
	my $start;
	$seconds = int($seconds / 10) ;
	$seconds *= 10;
	if($seconds == 0)
	{
		$start = time2str("%Y-%m-%d %H:%M:00", TedTools::mystr2time($trigTime));
	}
	else
	{
		$start = time2str("%Y-%m-%d %H:%M:$seconds", TedTools::mystr2time($trigTime));
	}


	TedTools::log_msg("starting Followup stuffs at: $start");

	# first query and populate previous 5 min. of timeseries, before trigTime
	# the 1min before trigger has tweets already written to tweeta, so no worries there
        ($peaked,$maxStc) = TedTools::pullTS(600,$start,$connect);


        until($waited > 300 ||  ($peaked == 1 && $waited >= 180) )
        {
                # check for next 30 sec. of tweets
                if( TedTools::checkTweets("$start+$waited",30,$connect) == 1 )
                {
			TedTools::log_msg("Proceeding to query next 30sec...");
                        ($peaked,$maxStc) = TedTools::pullTS("$start+$waited",30,$connect,$maxStc);

                        $refTweets = TedTools::getTweets("$start+$waited",30,$connect);
			$refTweetsGeo = TedGeo::geoCode($refTweets,"Gc");
			TedGeo::writeTweeta($refTweetsGeo);



			$waited = $waited + 30;
			if($peaked == 1)
			{ TedTools::log_msg("We've peaked! Still waiting for 3min minimum..."); }
                }
                else
                {
                        sleep 10;
			TedTools::log_msg("Waiting another 10 sec... no tweets in $start+$wated --> 30sec");
                }
	}




TedTools::log_msg("finishing sub waitingGame");
}

sub seis
{
	my $trigTime = shift;
	$numThreads++;
	TedTools::log_msg("Preparing seismograms in a separate thread...");
	my $lat = TedDB::geteventfeltinlat();
	my $lon = TedDB::geteventfeltinlong();
	print "$lat, $lon\n";

	my $refLinks = TedSeis::getStations($trigTime,$lat,$lon);
	my $link;
	foreach $link (@$refLinks)
	{
		print "$link\n";
	}
	
	$numThreads--;

my $pid = threads->self();
TedTools::log_msg("Ending seis thread $$pid");
threads->exit();
	
}

	


sub tweetGram
{
	my $trigTime = shift;
	my $waited = shift;
#$numThreads++;
	my $map_bef = 1;
	#my $output = system "python ./LIB/tweetGram.py \"$trigTime\" $map_bef $waited";
	TedTools::log_msg("TweetGram no longer made\n");
#$numThreads--;
#my $pid = threads->self();
#TedTools::log_msg("Ending tweetGram thread $$pid");
#threads->exit();
}

sub heatMap
{
	my $trigTime = shift;
	my $waited = shift;
#$numThreads++;
	my $map_bef = 1;
	#print "python ./LIB/heatMap.py \"$trigTime\" $map_bef $waited";
	#my $output = system "python ./LIB/heatMap.py \"$trigTime\" $map_bef $waited";
	TedTools::log_msg("Map no longer made\n");
#$numThreads--;
#my $pid = threads->self();
#TedTools::log_msg("Ending heatMap thread $$pid");
#threads->exit();
}


sub followTweet
{
	my $tweet = TedDB::getTweetFoll();

	my $lat = TedDB::geteventfeltinlat();
	my $lon = TedDB::geteventfeltinlong();

	if($spmute==1)
	{
		TedTools::log_msg("not sending any followup tweet. SPmute is on.");
	}
	elsif($spdev==1)
	{
		TedTools::log_msg("Generated, but not sending the followup tweet:");
		TedTools::log_msg("$tweet");
	}
	else
	{
		TedTools::log_msg("Sending Followup Tweet:");
		TedTools::log_msg("$tweet");
		TedTweet::tweetout($tweet,1,$lat,$lon);
	}
}


1;
