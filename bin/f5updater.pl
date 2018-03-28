#!/usr/bin/perl
#
# diffusion.pl - fast TV.com parser
#
# usage: diffusion <show> [<season>]
#

#die "usage: $0 <show> [<season>]\n" unless (@ARGV > 0 && @ARGV < 3);
#my ($show, $season) = @ARGV;
use 5.24.0 ;

use strict ;
use warnings ;

use WWW::Mechanize;

use File::HomeDir ;
use Digest::MD5 ;
use Net::SSH::Perl ;
use Net::SFTP ;

use Config::General ;
use Archive::Zip qw/ :ERROR_CODES :CONSTANTS /;
use Data::Dumper ;
my $configDir = File::HomeDir->my_home . "/.config/f5updater/" ;
my $cacheDir  = File::HomeDir->my_home . "/.cache/f5updater/" ;

mkdir $configDir unless ( -d $configDir ) ;
mkdir $cacheDir  unless ( -d $cacheDir  ) ;

my $conf = Config::General->new (
    -ConfigFile => $configDir."main.cnf",
    -AutoTrue => 1,
    -DefaultConfig => {
        "startPoint" => "https://downloads.f5.com/esd/product.jsp?sw=BIG-IP&pro=big-ip_v12.x",
        "awsCountryUrl" => "ire-f5",
        "skipDownload" => 1,
        "skipUpload" => 0,
        "forceUpload" => 0,
    },
    -MergeDuplicateOptions => 1
);

my %config = $conf->getall () ;

# Status vars
my $gotNewFiles = 0 ;
my ( $mainFile, $cksumFile ) ;

unless ( $config{ "skipDownload" } ) {
    my $m = WWW::Mechanize->new( autocheck => 0 );

    $m -> get( $config{"startPoint"} ) ;

    if ( $m->success () &&
             $m -> content () =~ /You must be logged/ ) {

        print "="x79,"\n";
        print "Submitting login information\n";

        $m -> submit_form (
            form_name => "login",
            fields => {
                userid => $config{"F5AccountUserID"} ,
                passwd => $config{"F5AccountPasswd"}
            }
        );

        unless ( $m->success() ) {
            print STDERR "Error submitting login !\n" ;
            die ;
        }

        print "="x79,"\n";
        my $geoUpdLink ;
        foreach ($m -> links () ) {
            if ( $_->text() && $_->text() =~ /GeoLocationUpdates/ ) {
                $geoUpdLink = $_ ;
                last ;
            }
            #print "Available link: ", $_->text(), " pointing to ", $_->url(), Dumper ($_),  "\n" ;
        }

        print "Follow link, shoud get EULA\n";
        $m -> get ($geoUpdLink) ;
        unless ( $m -> content () =~ /LicenseAgreement/ ) {
            print STDERR "Strange, did not get the EULA page\n" ;
            die ;
        }
        $m -> submit_form ( form_name => "LicenseAgreement" ) ;

        #print Dumper ( $m -> content () ) ;

        unless ( $m->success() ) {
            print STDERR "Error submitting EULA !\n" ;
            die ;
        }

        print "="x79,"\n";

        my @dlLinks ;
        foreach ($m -> links () ) {
            if ( $_->text() && $_->text() =~ /ip-geolocation-/ ) {
                print "Available link: ", $_->text(), " pointing to ", $_->url(),  "\n" ;
                push @dlLinks, $_ ;
            }
        }

        foreach (@dlLinks) {
            my $filename = $_ -> text () ;

            print "="x79,"\n";
            print "Processing ", $filename , "\n";

            if ($filename =~ /\.(md5|sha)/ ) {
                $cksumFile = $filename ;
            } else {
                $mainFile = $filename ;
            }

            if ( -e $cacheDir.$filename ) {
                print "  Already downloaded !\n" ;
            } else {

                print "GET From " , $_->url() , " at " , $m->base () , "\n" ;
                my $res = $m -> get ( $_ ) ;

                unless ( $m->success() ) {
                    print STDERR "Error fetching link page for $filename !\n" ;
                    die ;
                }

                foreach ($m -> links () ) {
                    if ( $_->url() && index( $_->url(), $filename ) >= 0 ) {
                        print "Available link: ", $_->text(), " pointing to ", $_->url(), "\n" ;

                        if ($_->url() =~ /amazonaws/ && !($_->url() =~ /\Q${config{'awsCountryUrl'}}\E/) ) {
                            print "Skip amazon link too far\n" ;
                            next ;
                        }

                        $m -> show_progress ( 1 ) ;
                        $m -> get ( $_ ) ;
                        $m -> save_content ( $cacheDir.$filename ) ;
                        #push @dlLinks, $_ ;

                        if ( $m->success() ) {
                            print "Fetching ok: ",$m->status(),"\n" ;
                            last ;
                        } else {
                            print "Error fetching from this url, trying another\n" ;
                            $m -> back () ;
                        }
                    }
                }

                # "Return" to download page to get correct base uri
                $m -> back () ;
            }
        }
    } else {
        print STDERR "Strange, did not get the login page !\n" ;
        die ;
    }

} else {
    # Skip Download asked, find the latest files in the cache directory
    opendir ( DIR, $cacheDir ) or die $!;

    while (my $file = readdir ( DIR ) ) {
        next unless ( $file =~ /\.zip$/ ) ;

        if ( $mainFile ) {
            $mainFile = $file if ( ( $file cmp $mainFile ) == 1 );
        } else {
            $mainFile = $file ;
        }

    }

    closedir ( DIR ) ;

    $cksumFile = $mainFile . ".md5" if ( $mainFile ) ;
}

if ( ( $gotNewFiles || ! $config{'forceUpload'} )
         && $mainFile && !$config{'skipUpload'} ) {

    print "="x79,"\n";
    print "Verify download\n";

    if ( $cksumFile && $mainFile ) {
        my $md5 = Digest::MD5 -> new ;

        open (my $fh, '<', $cacheDir.$mainFile) or die "Can't open '$cacheDir.$mainFile': $!" ;
        binmode ($fh) ;

        $md5 -> addfile ( $fh ) ;
        my $digest = $md5->hexdigest () . "  " . $mainFile ;
        close $fh ;

        open ($fh, '<', $cacheDir.$cksumFile) or die "Can't open '$cacheDir.$cksumFile': $!" ;
        my $verifSum = <$fh> ;
        chomp ( $verifSum ) ;
        close $fh ;

        say "Calculated digest is $digest" ;
        say "Downloaded digest is $verifSum" ;
        if ( $verifSum eq $digest ) {
            say " - matching !" ;
        } else {
            say " - error !" ;
            unlink $cacheDir.$cksumFile ;
            unlink $cacheDir.$mainFile ;
            die "File doesn't match checksum - deleted !\n";
        }
    }

    print "="x79,"\n";
    print "Uploading database\n";

    my $zip = Archive::Zip->new();

    unless ( $zip->read( $cacheDir.$mainFile ) == AZ_OK ) {
        # Make sure archive got read
        unlink $cacheDir.$cksumFile ;
        unlink $cacheDir.$mainFile ;

        die 'Zip archive not parseable - deleted';
    }

    my @files = $zip->memberNames(); # Lists all members in archive

    foreach my $dev ( keys %{$config{"bigipAccess"}} ) {
        my $device = $config{'bigipAccess'}{$dev} ;

        print "Connecting to $dev using ", $device->{login},"@",$device->{host}, "\n" ;
        my $sftp = Net::SFTP->new(
            $device->{host},
            (
                user => $device->{login},
                password => $device->{password},
                ssh_args => { options => [ "MACs +hmac-sha1", "KexAlgorithms +diffie-hellman-group1-sha1" ] }
            )
        ) ;

        unless ( $sftp -> put ( $cacheDir.$mainFile, "/var/tmp/$mainFile" ) ) {
            print STDERR "Unable to upload to ", $device -> {host}, "\n" ;
            next ;
        }

        my $ssh = Net::SSH::Perl->new(
            $device->{host},
            (
                options => [ "MACs +hmac-sha1", "KexAlgorithms +diffie-hellman-group1-sha1" ],
                identity_files => [ "" ]
            )
        ) ;

        unless ( $ssh -> login ( $device->{login}, $device->{password} ) ) {
            print STDERR "Error login to device\n" ;
            next ;
        }

        my ($out, $err, $exit) ;
        ($out, $err, $exit) = $ssh -> cmd ( "unzip -o -j /var/tmp/$mainFile -d /var/tmp/" ) ;
        unless ( $exit == 0 ) {
            print STDERR "Error while unziping file !\n" ;
            print STDERR "Unzip output: $out, $err, $exit\n" ;
            next ;
        }

        ($out, $err, $exit) = $ssh -> cmd ( "/bin/rm /var/tmp/$mainFile" ) ;

        foreach $_ (@files) {
            next unless /\.rpm/ ;

            print "Installing $_ ... " ;

            ($out, $err, $exit) = $ssh -> cmd ( "/usr/local/bin/geoip_update_data -f /var/tmp/$_" ) ;
            if ( $exit == 0 ) {
                print " ok !\n" ;
            } else {
                print " error !\n" ;
                print "Geoipupdate output: $out, $err, $exit\n" ;
            }

            ($out, $err, $exit) = $ssh -> cmd ( "/bin/rm /var/tmp/$_" ) ;
        }

    }

}

__END__
