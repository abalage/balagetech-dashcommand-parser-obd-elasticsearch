#!/usr/bin/perl

use strict;
use warnings;
use File::Basename qw( fileparse );
use Pod::Usage;
use Getopt::Long qw(GetOptions);
use Carp;
use POSIX qw(strftime);
use DateTime;
use Text::CSV qw( csv );
#use JSON::XS;
use Regexp::Common qw /net/;
# https://stackoverflow.com/questions/627661/how-can-i-output-utf-8-from-perl
use utf8;
use open qw/:std :utf8/;

my $man;
my $help;
my $dash;
my $date;
my $elastic;

GetOptions(
    'help|?'   => \$help,
    'man'      => \$man,
    'dash|d=s' => \$dash,
    'elk|e=s'  => \$elastic
) or pod2usage(2);
pod2usage(-verbose => 1) if $help;
pod2usage(-verbose => 2) if $man;

if (not defined($elastic)){
    croak "Elasticsearch node is not set. Please configure it with the following switch: --elk, -e <IP>:9200\n";
}

sub parse_date_from_filename {
    my $file = shift;
    my $dt;
    my $hour=0;

    # borrowed from: https://stackoverflow.com/questions/241579/what-is-the-easiest-or-most-effective-way-to-convert-months-abbreviation-to-a-n
    my %mon2num = qw(
        jan 1  feb 2  mar 3  apr 4  may 5  jun 6
        jul 7  aug 8  sep 9  oct 10 nov 11 dec 12
    );

    my($filename, $dirs, $suffix) = fileparse($file, qr/\.[^.]*/);

    # Data Log Jun 02 2019 02_45 PM.csv
    if ( $filename =~ m/^Data\sLog\s(.+)\s([0-9]{2})\s([0-9]{4})\s([0-9]{2}).([0-9]{2})\s(.+)$/i ) {
        if ( $6 eq "PM" ) {
            $hour = $4;
            $hour+=12;
        }
        else {
            $hour = $4;
        }
        $dt = DateTime->new(
            year        => $3,
            month       => $mon2num{lc($1)},
            day         => $2,
            hour        => $hour,
            minute      => $5,
            second      => '00',
            time_zone   => "Europe/Budapest",
        );
    }

    $date = $dt->ymd("-");

#    print $dt->iso8601 . "\n";
#    exit;

    return $dt;
}

sub increment_timestamp_from_records {
    my $dt             = shift;
    my $seconds_etalon = shift;
    my $epoch          = $dt->epoch;
    $epoch             = ($epoch + $seconds_etalon);

    return $epoch;
}

sub parse_dashcommand_csv {
    # http://lcsi.umh.es/docs/pfcs/PFC_TFG_Bocanegra_Fernando.pdf
    # https://www.palmerperformance.com/download/docs/DashCommand_User_Manual.pdf
    # https://www.palmerperformance.com/download/CALC_PID_Reference.pdf
    my $file                = shift;
    my $csv                 = Text::CSV->new({ binary => 1, auto_diag => 1, sep_char => ',' }) or croak Text::CSV->error_diag;
    my @AoH                 = ();
    my $date_from_filename  = &parse_date_from_filename($file);
    my $fh;

    open($fh, "<:encoding(UTF-8)", "$file") or croak "Could not open '$file' $!\n";

    # parse first header
    my @hdr = $csv->header($fh);
    $csv->column_names(@hdr);

    # from the csv header we know the index numbers we need from the arrays of parsed records
    # almost each record type has its own timestamp record, we need to map them together
    # gps (13..29. 12=ts)
    # sae (30..48, 30=ect.ts, 33=rpm.ts 35=vss.ts 38=sparkadv.ts 40=iat.ts 43=maf.ts 47=baro.ts )
    # calc (116..207 , 116=ts, 122=ts, 130=ts, 139=ts, 162=ts, 165=ts, 168=ts 174=ts 177=ts 180=ts 205=ts)
#   my @data_indexes      = qw ( 12 13 15 18 21 24 26 29 30 32 33 34 35 37 38 39 40 42 43 45 47 48 116 118 122 124 130 132 139 141 162 164 165 167 168 170 174 175 177 179 180 181 205 207 );
#   my @timestamp_indexes = qw ( 12                      30    33    35    38    40    43    47    116     122     130     139     162     165     168     174     177     180     205     );

    my %indexes_of_values_and_timestamps = (
        # value => timestamp
        # index numbers
            13  => 12,
            15  => 12,
            18  => 12,
            21  => 12,
            24  => 12,
            26  => 12,
            29  => 12,
            32  => 30,
            34  => 33,
            37  => 35,
            39  => 38,
            42  => 40,
            45  => 43,
            48  => 47,
            118 => 116,
            124 => 122,
            132 => 130,
            141 => 139,
            164 => 162,
            167 => 165,
            170 => 168,
            175 => 174,
            179 => 177,
            181 => 180,
            207 => 205,
    );

    my $counter = 0;
    while (my $row = $csv->getline ($fh)) {
        # getline returns arrayref
        if ( $counter == 0 ) {
            # second header, not needed
            $counter++;
            next;
        }
        else {
            # timestamp: rounding milliseconds to closest seconds
            my $seconds_etalon = int((@$row[2] + 500) / 1000); # Frame Time (ms)
            # borrowed from: https://stackoverflow.com/questions/20385067/how-to-round-off-timestamp-in-milliseconds-to-nearest-seconds

            my $ts_etalon = &increment_timestamp_from_records($date_from_filename, $seconds_etalon);

            #### process row ####
            my %document=();

            foreach my $ts_index (values(%indexes_of_values_and_timestamps)) {
                if ( @$row[$ts_index] eq "" ){
                    # some frames have no data at all
                    next;
                }
                # @$row[2] contains the etalon timestamp
                # we round the actual timestamp and check whether it matches the etalon

                my $seconds_current_index = int((@$row[$ts_index] + 500) / 1000);
                if ( $seconds_current_index == $seconds_etalon ) {
                    # find out the keys belonging to the timestamp
                    my @matching_keys = grep { $indexes_of_values_and_timestamps{$_} eq $ts_index } keys %indexes_of_values_and_timestamps;

                    foreach my $key (@matching_keys) {
                        if ( $hdr[$key] =~ m/^aux.+/i ){
                            %document = (
                                'geo.location' => {
                                    "lon" => @$row[15],
                                    "lat" => @$row[13],
                                },
                                'aux.gps.altitude' => @$row[18],
                                'aux.gps.course' => @$row[26],
                                'aux.gps.speed' => @$row[29],
                            );

                        }
                        # sometimes its empty sometimes its 'N/A', we do not need them
                        if ( @$row[$key] ne "N/A" ) {
                            $document{$hdr[$key]} = @$row[$key];
                        }
                    }
                    $document{'frame number'}   = @$row[0];
                    $document{'@timestamp'}     = strftime('%Y-%m-%dT%H:%M:%S', gmtime($ts_etalon));
                }
            }

            # use Data::Dumper;
            # print Dumper(\%document) . "\n";
            push @AoH, \%document;
        }
    }

    close($fh) or croak "Could not close '$file' $!\n";
    return \@AoH;
}

sub send_to_elastic {
    my $index = shift; # FIXME sanity check needed
    my $data  = shift; # arrayref

    if ( ! $RE{net}{IPv4}->matches($elastic) ) {
        croak "Provided address is not an IPv4 address\n";
    }

    use Search::Elasticsearch;
    my $es = Search::Elasticsearch->new(
        nodes => [
            "$elastic"
        ],
        trace_to => ['File',"$date.log"]
    );

    my $bulk = $es->bulk_helper(
        index   => $index,
        type    => '_doc',
    );

    foreach my $hashref (@$data) {
        $bulk->add_action(
            index => { source => { %$hashref }},
        );
    }

    $bulk->flush;

    return 1;
}

################
my $dashdata = ();

if ( defined($dash) ) {
    $dashdata = &parse_dashcommand_csv($dash);
}
else {
    pod2usage(-verbose => 1);
}

&send_to_elastic("dashcommand-$date",$dashdata); # arrayref
