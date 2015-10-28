#!/usr/bin/env perl
#
# Bit.ly click distribution histogram
#
# Usage:
# ./script/run_with_carton.sh ./script/mediawords_bitly_click_distribution.pl [--limit 200] > bitly_click_distrib.csv
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2013";
use MediaWords::CommonLibs;
use MediaWords::DB;
use MediaWords::Util::Bitly;
use MediaWords::Util::DateTime;
use MediaWords::Util::SQL;

use Getopt::Long;
use Readonly;
use DateTime;

sub main
{
    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );

    my $limit = 200;

    Readonly my $usage => <<"EOF";
Usage: $0 [--limit $limit]
EOF

    Getopt::Long::GetOptions( 'limit=i' => \$limit, ) or die $usage;

    my $db = MediaWords::DB::connect_to_db;

    my $publish_timestamp_lower_bound = DateTime->new( year => 2008, month => 01, day => 01 )->epoch;
    my $publish_timestamp_upper_bound = DateTime->now()->epoch;

    # Buckets for the histogram
    my $buckets = [
        { from => undef,       to => -7 * 24 },
        { from => -7 * 24 + 1, to => -6 * 24 },
        { from => -6 * 24 + 1, to => -5 * 24 },
        { from => -5 * 24 + 1, to => -4 * 24 },
        { from => -4 * 24 + 1, to => -3 * 24 },
        { from => -3 * 24 + 1, to => -2 * 24 },
        { from => -2 * 24 + 1, to => -1 * 24 },
        { from => -1 * 24 + 1, to => 0 },
        { from => 1,           to => 1 * 24 },
        { from => 1 * 24 + 1,  to => 2 * 24 },
        { from => 2 * 24 + 1,  to => 3 * 24 },
        { from => 3 * 24 + 1,  to => 4 * 24 },
        { from => 4 * 24 + 1,  to => 5 * 24 },
        { from => 5 * 24 + 1,  to => 6 * 24 },
        { from => 6 * 24 + 1,  to => 7 * 24 },
        { from => 7 * 24 + 1,  to => undef },
    ];

    say STDERR "Fetching (up to) $limit story IDs...";
    my $story_ids = $db->query(
        <<EOF,
        SELECT object_id AS stories_id
        FROM bitly_processing_results
        ORDER BY RANDOM()
        LIMIT ?
EOF
        $limit
    )->flat;

    my $min_publish_timestamp = undef;
    my $max_publish_timestamp = undef;

    foreach my $stories_id ( @{ $story_ids } )
    {
        my $story = $db->find_by_id( 'stories', $stories_id );
        unless ( $story )
        {
            say STDERR "Unable to find story with ID $stories_id";
            next;
        }

        my $publish_date = $story->{ publish_date };
        unless ( $publish_date )
        {
            say STDERR "Publish date is unset for story $stories_id";
            next;
        }

        my $publish_timestamp = MediaWords::Util::SQL::get_epoch_from_sql_date( $publish_date );
        if ( $publish_timestamp <= $publish_timestamp_lower_bound )
        {
            say STDERR "Publish timestamp is lower than the lower bound for story $stories_id";
            next;
        }
        if ( $publish_timestamp >= $publish_timestamp_upper_bound )
        {
            say STDERR "Publish timestamp is bigger than the upper bound for story $stories_id";
            next;
        }

        # Round timestamp to the nearest day because that's what Bitly.pm does
        my $publish_datetime = gmt_datetime_from_timestamp( $publish_timestamp );
        $publish_datetime->set( hour => 0, minute => 0, second => 0 );
        $publish_timestamp = $publish_datetime->epoch;

        $min_publish_timestamp = $publish_timestamp
          if !defined $min_publish_timestamp or $min_publish_timestamp > $publish_timestamp;
        $max_publish_timestamp = $publish_timestamp
          if !defined $max_publish_timestamp or $max_publish_timestamp < $publish_timestamp;

        my $story_stats = MediaWords::Util::Bitly::read_story_stats( $db, $stories_id );
        unless ( $story_stats )
        {
            die "Unable to fetch Bit.ly story stats for story $stories_id";
        }

        foreach my $bitly_hash ( keys %{ $story_stats->{ data } } )
        {
            foreach my $bitly_clicks ( @{ $story_stats->{ data }->{ $bitly_hash }->{ clicks } } )
            {
                foreach my $link_click ( @{ $bitly_clicks->{ link_clicks } } )
                {
                    my $clicks     = $link_click->{ clicks } + 0;
                    my $dt         = $link_click->{ dt } + 0;
                    my $diff       = $dt - $publish_timestamp;
                    my $diff_hours = int( $diff / 60 / 60 );

                    if ( $clicks > 0 )
                    {
                        my $bucket_found = 0;
                        foreach my $bucket ( @{ $buckets } )
                        {
                            my $bucket_from = $bucket->{ from };
                            my $bucket_to   = $bucket->{ to };

                            unless ( defined $bucket->{ clicks } )
                            {
                                $bucket->{ clicks } = 0;
                            }

                            if ( ( !defined( $bucket_from ) ) or $bucket_from <= $diff_hours )
                            {
                                if ( ( !defined( $bucket_to ) ) or $bucket_to >= $diff_hours )
                                {

                                    if ( $bucket_found )
                                    {
                                        die "More than one bucket was found for hours $diff_hours";
                                    }
                                    else
                                    {
                                        $bucket_found = 1;
                                    }

                                    $bucket->{ clicks } += $clicks;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    say STDERR "Min. publish timestamp: $min_publish_timestamp";
    say STDERR "Max. publish timestamp: $max_publish_timestamp";

    say '"Hours since \'publish_date\'","Clicks"';
    foreach my $bucket ( @{ $buckets } )
    {
        print '"';
        print( $bucket->{ from } // 'inf' );
        print ' - ';
        print( $bucket->{ to } // 'inf' );
        print '",' . $bucket->{ clicks } . "\n";
    }

    say STDERR "Done.";
}

main();
