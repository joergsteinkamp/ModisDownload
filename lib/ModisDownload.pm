package ModisDownload;

use 5.020001;
use strict;
use warnings;
use LWP::UserAgent;
use File::Path qw(make_path);
use File::Basename;
use Date::Simple;
use List::Util qw(any min max);

require Exporter;
our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration       use ModisDownload ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = ( 'all' => [ qw() ] );
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );
our @EXPORT = qw(loadCache initCache refreshCache getVersions getURLs modisDownload isGlobal);

our $VERSION = '0.01';

# Some variables used by several subroutines
my $BASE_URL = "http://e4ftl01.cr.usgs.gov";
my @DATA_DIR =("MOLA", "MOLT", "MOTA");

my %MODIS = ();
my %MODISDates = ();
my %MODISGlobal = ();
my $ModisCacheFile = "Modis.pl";
my $ModisDatesCacheFile = "ModisDates.pl";
my $ModisGlobalCacheFile = "ModisGlobal.pl";
my $CacheDir;

my $defaultMODISVersion = "005";

# Check the OS and exit if not implemented yet
if ($^O eq "linux") {
  $CacheDir = "$ENV{HOME}/.cache/ModisDownload";
} else {
  die("OS \"$^O\" not implemented!\n");
}

#######################################################################
### For debuging and informations

# returns the cached products data hash
sub getModisProducts() {
  return(%MODIS);
}

#returns the reference to the dates array
sub getModisDates($) {
  my $prod = shift;
  return($MODISDates{$prod});
}

# returns the cached global grid check hash
sub getModisGlobal() {
  return(%MODISGlobal);
}

sub getVersions($) {
  my $prod=shift;
  my @versions = ();
  foreach (keys %MODIS) {
    next if (! /$prod/);
    s/$prod.//;
    push(@versions, $_);
  }
  return(@versions);
}

########################################################################
### returns the cached global grid check hash
sub getAvailVersions($) {
  my $prod = shift;
  my @prodVersions = ();
  foreach (keys %MODIS) {
    next if (! /$prod/);
    s/$prod\.//;
    push(@prodVersions, $_);
  }
  return(@prodVersions);
}

########################################################################
### Functions pulling file list for desired Modis product and date,

sub getDateFullURLs($$) {
  my $prod = shift;
  my $date = shift;
  
  my @flist = ();

  my $ua = new LWP::UserAgent;
  my $response = $ua->get("${BASE_URL}/$MODIS{$prod}/$prod/$date");
  
  unless ($response->is_success) {
   die $response->status_line;
  }

  my $content = $response->decoded_content();
  my @content = split("\n", $content);
  foreach (@content) {
    next if (!/href="M/);
    next if (/hdf.xml/);
    s/.*href="//;
    s/".*//;
    push(@flist, "${BASE_URL}/$MODIS{$prod}/$prod/$date/$_");
  }
  return(@flist);
}

########################################################################
### Functions to set up and refresh the cached data

# check is Product is global or on sinusoidal grid (with h??v?? in name)
sub isGlobal($) {
  my $prod = shift;
  my $retval = 1;

  if (! any { /$prod/ } keys %MODIS) {
    warn("\"$prod\" is not in the MODIS product list: Check name or refresh the cache.\n");
    return(-1);
  }
  
  my @flist = getDateFullURLs($prod, ${$MODISDates{$prod}}[0]);
  my $teststr = $flist[0];
  $teststr =~ s/.*\///;
  $retval = 0 if ($teststr =~ /h[0-9]{2}v[0-9]{2}/);
  return($retval);
}

# Downloads the list of available data from the server
# return a hash with the data as key and the directory on
# the server as value.
sub getAvailData () {
  my %lookupTable = ();
  my $ua = new LWP::UserAgent;
  foreach my $subdir (@DATA_DIR) {
    my $response = $ua->get("${BASE_URL}/${subdir}");

    unless ($response->is_success) {
      die $response->status_line;
    }

    my $content = $response->decoded_content();
    my @content = split("\n", $content);
    foreach (@content) {
      next if (!/href="M/);
      s/.*href="//;
      s/\/.*//;

      print "Key already exists\n" if exists $lookupTable{$_};
      print "Key already defined\n" if defined $lookupTable{$_};
      print "True\n" if $lookupTable{$_};
      
      $lookupTable{$_} = $subdir;
    }
  }
  return %lookupTable;
}

# get the available directories, named by date (YYYY.MM.DD) under
# which the hdf files are. This does not ensure that the files
# are really there.
sub getAvailDates($) {
  my $refModis = shift;
  my %modis = %$refModis;

  my %lookupTable = ();
  
  my $ua = new LWP::UserAgent;
  foreach my $key (keys %modis) {
    my @dates=();
    my $response = $ua->get("${BASE_URL}/$modis{$key}/$key");
    
    unless ($response->is_success) {
      die $response->status_line;
    }

    my $content = $response->decoded_content();
    my @content = split("\n", $content);
    foreach (@content) {
      next if (!/href="20[0-9]{2}\.[0-9]{2}\.[0-9]{2}/);
      s/.*href="//;
      s/\/.*//;
      push(@dates, $_);
    }
    $lookupTable{$key} = "['".join("', '", @dates)."']";
  }
  return %lookupTable;
}

# Creates the cache, if desired/needed
sub setCache ($) {
  # <0: just return -1;
  # 0:  only if the directory is already present else return -2;
  # 1:  initialaize only if the files are not yet there and have a size > 0 else load present cache
  # >1: force refresh
  my $force = shift;

  return(-1) if ($force < 0);
  return(-2) if ($force == 0 &&  ! -d $CacheDir);

  if ($force < 2 && -f "$CacheDir/$ModisCacheFile") {
    if (-s "$CacheDir/$ModisCacheFile") {
      %MODIS = do "$CacheDir/$ModisCacheFile";
      
       if (-s "$CacheDir/$ModisDatesCacheFile") {
         %MODISDates = do "$CacheDir/$ModisDatesCacheFile";

         if (-s "$CacheDir/$ModisGlobalCacheFile") {
           %MODISGlobal = do "$CacheDir/$ModisGlobalCacheFile";
           return(0);
         } else {
           warn("Cache file \"$CacheDir/$ModisGlobalCacheFile\" is empty. Trying to recreate it.\n");
         }
       } else {
         warn("Cache file \"$CacheDir/$ModisDatesCacheFile\" is empty. Trying to recreate it.\n");
       }
    } else {
      warn("Cache file \"$CacheDir/$ModisCacheFile\" is empty. Trying to recreate it.\n");
    }
  }

  if ( ! -d $CacheDir ) {
    make_path($CacheDir) or warn("Could not create cache dir ('$CacheDir'): $!\n");
  }

  my $fhd;

  ### Set up the MODIS products cache
  my %lookupTable = getAvailData();
  my $N = keys(%lookupTable);

  open($fhd, ">", "$CacheDir/$ModisCacheFile") or 
    warn("cannot open \"$CacheDir/$ModisCacheFile\" for writing: $!\n");

  for (keys %lookupTable) {
    print  $fhd "'$_' => '$lookupTable{$_}',\n";
  }
  close($fhd) or warn "close \"$CacheDir/$ModisCacheFile\" failed: $!";
  %MODIS = do "$CacheDir/$ModisCacheFile";

  ### Set up the MODIS dates cache
  %lookupTable = getAvailDates(\%MODIS);
  $N = keys(%lookupTable);

  open($fhd, ">", "$CacheDir/$ModisDatesCacheFile") or
    warn("cannot open \"$CacheDir/$ModisDatesCacheFile\" for writing: $!\n");

  for (keys %lookupTable) {
    print  $fhd "'$_' => $lookupTable{$_},\n";
  }
  close($fhd) or warn "close \"$CacheDir/$ModisDatesCacheFile\" failed: $!";
  %MODISDates = do "$CacheDir/$ModisDatesCacheFile";

  ### Set up the MODIS global check cache
  open($fhd, ">", "$CacheDir/$ModisGlobalCacheFile") or
    warn("cannot open \"$CacheDir/$ModisGlobalCacheFile\" for writing: $!\n");

  for (keys %MODIS) {
    my $check = isGlobal($_);
    $MODISGlobal{$_} = $check;
    print $fhd "'$_' => $check,\n";
  }
  return(0);
}

### END: Functions to set up and refresh the cached data
########################################################################

# create a list of files to download
sub createDownloadURLs(@) {
  my $nArgs = @_;
#    die("Wrong number of arguments to \"getFileList\": $nArgs\n") if ($nArgs != 2 || $nArgs != 4);
  my $prod = shift;
  my $refArr = shift;
  my @dateRange = @$refArr;
  my $nDate = @dateRange;
  my @h = ();
  my @v = ();
  if ($nArgs == 4) {
    $refArr = shift;
    @h = @$refArr;
    $refArr = shift;
    @v = @$refArr;
  }

  my @URLs = ();
    
  if ($nArgs==2 && !$MODISGlobal{$prod}) {
    warn("Product \"$prod\"is sinusoidal, but no \"h\" and \"v\" arguments were supplied to \"createDownloadURLs\".\n");
    return(-99);
  }
  
  if ($nDate == 1) {
    if (! any { /$dateRange[0]/ } @{$MODISDates{$prod}}) {
      warn("No data available for desired date: $prod @ $dateRange[0].\n");
      return(-99);
    }
    push(@dateRange, $dateRange[0]);
  }
  s/\./\-/g foreach (@dateRange);
    
  warn ("Product \"$prod\"is global, but 4 arguments were supplied to \"createDownloadURLs\".\n") 
    if ($nArgs==4 && $MODISGlobal{$prod});

  foreach (@{$MODISDates{$prod}}) {
    s/\./\-/g;
    my $date = Date::Simple->new($_);
    next if ($date - Date::Simple->new($dateRange[0]) < 0);
    next if ($date - Date::Simple->new($dateRange[1]) > 0);

    my @fullURLs = getDateFullURLs($prod, $date->format("%Y.%m.%d"));

    if (!$MODISGlobal{$prod}) {
      foreach my $i (min(@h)..max(@h)) {
        foreach my $j (min(@v)..max(@v)) {
          my $pat = sprintf("h%02iv%02i", $i, $j);
          my @newURLs = ();
          foreach (@fullURLs) {
            if (/$pat/) {
              push(@newURLs, $_);
            }
          }

          my $nNewURLs = @newURLs;
          if ($nNewURLs == 1) {
            push(@URLs, $newURLs[0]);
          } elsif ($nNewURLs < 1) {
            warn(sprintf("$prod: Missing file for %s @ %s.\n", $pat, $date->format("%Y.%m.%d")));
          } else { 
          # check for duplicate files here and choose the latest one
            warn(sprintf("$prod: %i files for %s @ %s, choosing the newest.\n", $nNewURLs, $pat, $date->format("%Y.%m.%d")));
            my $createDate = $newURLs[0];
            $createDate =~ s/\.hdf$//;
            $createDate =~ s/^.*\.//g;
            $createDate = int($createDate);
            my $newest = 0;
            for (my $k=0; $k < $nNewURLs; $k++) {
              s/\.hdf$//;
              s/^.*\.//g;
              if (int($_) > $createDate) {
                $newest = $k;
                $createDate = int($_);
              }  
            }
            push(@URLs, $newURLs[$newest]);
          }
        }
      }
    } else {
      my $nURLs = @fullURLs;
      if ($nURLs == 1) {
        push(@URLs, $fullURLs[0]);
      } elsif ($nURLs < 1) {
        warn(sprintf("$prod: Missing file @ %s.\n", $date->format("%Y.%m.%d")));
      } else { 
      # check for duplicate files here and choose the latest one
        warn(sprintf("$prod: %i files @ %s, choosing the newest.\n", $nURLs, $date->format("%Y.%m.%d")));
        my $createDate = $fullURLs[0];
        $createDate =~ s/\.hdf$//;
        $createDate =~ s/^.*\.//g;
        $createDate = int($createDate);
        my $newest = 0;
        for (my $k=0; $k < $nURLs; $k++) {
          s/\.hdf$//;
          s/^.*\.//g;
          if (int($_) > $createDate) {
            $newest = $k;
            $createDate = int($_);
          }  
        }
        push(@URLs, $fullURLs[$newest]);
      }
    }
  }
  return(@URLs);
}

########################################################################
### Function returning the URL file list

sub getURLs(@) {
  my $nArgs = @_;
    
  my $prod = shift;

  if (! any { /$prod/ } (keys %MODIS)) {
    warn("Product \"$prod\" unknown.\n");
    return(-99);
  }
  my $version;
  $version = shift if ($nArgs==3 || $nArgs==5);
  my @dates = ();
  my @h = ();
  my @v = ();
  my $refArr = shift;
  @dates = @$refArr;
  if ($nArgs>3) {
    $refArr = shift;
    @h = @$refArr;
    $refArr = shift;
    @v = @$refArr;
  }
  my @availVersions = getAvailVersions($prod);

  if (defined($version)) {
    if (any { /$version/ } @availVersions) {
      $prod = "${prod}.${version}";
    } else {
      warn("Version $version not available for $prod (available: ".join(" ,", @availVersions).").\n");
      return(-99);
    }
  } else {
    $version = $defaultMODISVersion;
    if (any { /$version/ } @availVersions) {
      $prod = "${prod}.${version}";
    } else {
      foreach (@availVersions) {
        $version = $_ if (int($_) > int($version));
      }
      $prod = "${prod}.${version}";
    }
  }
  my @URLs = ();
  my $hLength = @h;
  if ($hLength) {
    @URLs = createDownloadURLs($prod, \@dates, \@h, \@v);
  } else {
    @URLs = createDownloadURLs($prod, \@dates);
  }
  return(@URLs);
}

########################################################################
### Function for download
sub modisDownload (@) {
  my $nArgs = @_;
  my $refURL = shift;
  my $success = 0;
  $success=1 if ("$refURL" ne "");
  if (!$success) {
    warn("No URL(s) given!\n");
    return(-1);
  }
  my $refDestination;
  my $forceReload = 0;
  my $verbose = 0;
  
  if ($nArgs == 1) {
    $refDestination = ".";
  } else {
    $refDestination = shift;
  }

  $verbose = 1 if ($nArgs > 2);
  $forceReload = 1 if ($nArgs > 3);

  my @URL = ();
  my @destination = ();

    # check if these are a reference or a single file first
  if ($refURL =~ /^ARRAY\(0x[a-z0-9]{7}\)$/) {
    @URL = @$refURL;
  } else {
    $URL[0] = $refURL;
  }
  if ($refDestination =~ /^ARRAY\(0x[a-z0-9]{7}\)$/) {
    @destination = @$refDestination;
  } else {
    $destination[0] = $refDestination;
  }
  my $nUrl = @URL;
  my $nDestination = @destination;

  if ($nDestination > $nUrl) {
    warn("More file destinations than URLs given! Will use the first ones only\n");
  } elsif ($nDestination > 1 && $nUrl > $nDestination) {
    warn("More URLs than destinations given. STOP!\n");
    return(-2);
  } elsif ($nDestination == 1 && $nUrl > 1) {
    if (! -d $destination[0]) {
      $success = 0;
      make_path($destination[0]) and $success = 1;
      if (!$success) {
        warn("Cannot create directory \"$destination[0]\": $!\n");
        return(-4);
      }
    }
    my $dir = $destination[0];
    for (my $i=0; $i < $nUrl; $i++) {
      $destination[$i] = $dir."/".basename($URL[$i]);
    }
  } elsif ($nDestination == 1 && $nUrl == 1) {
    if (-d $destination[0]) {
      $destination[0] = $destination[0]."/".basename($URL[0]);
    } elsif (! -f $destination[0]) {
      make_path($destination[0]) and $success = 1;
      if (!$success) {
        warn("Cannot create directory \"$destination[0]\": $!\n");
        return(-4);
      }
      $destination[0] = $destination[0]."/".basename($URL[0]);
    }
  }
  
  # what happens if the destination list contains none existing paths?!

  # adjusted from http://stackoverflow.com/questions/6813726/continue-getting-a-partially-downloaded-file
  my $ua = LWP::UserAgent->new();

  for (my $i=0; $i < $nUrl; $i++) {
    unlink($destination[$i]) if ($forceReload && -f $destination[$i]);
    $success = 1;
    open(my $fh, '>>:raw', $destination[$i]) or $success = 0;
    if (!$success) {
      warn("Cannot open \"$destination[$i]\": $!\n");
      return(-8);
    }
    my $bytes = -s $destination[$i];
    my $res;
    if ( $bytes && ! $forceReload) {
      print "resume $URL[$i] -> $destination[$i] ($bytes) " if ($verbose);
      $res = $ua->get(
        $URL[$i],
        'Range' => "bytes=$bytes-",
        ':content_cb' => sub { my ( $chunk ) = @_; print $fh $chunk; }
      );
    } else {
      print "$URL[$i] -> $destination[$i] " if ($verbose);
      $res = $ua->get(
        $URL[$i],
        ':content_cb' => sub { my ( $chunk ) = @_; print $fh $chunk; }
      );
    }
    close $fh;

    my $status = $res->status_line;
    if ( $status =~ /^(200|206|416)/ ) {
      print "OK\n" if ($verbose && $status =~ /^20[06]/);
      print "already complete\n" if ($verbose && $status =~ /^416/);
    } else {
      print "DEBUG: $status what happend?";
    }
  }
  return(0);
}

########################################################################
### Exported wrapper functions

sub loadCache() {
  my $retval = setCache(0);
  warn("No cache dir available run \"initCache\" first.\n") if ($retval == -2);
  return $retval;
}

sub initCache() {
  return setCache(1);
}

sub refreshCache() {
  return setCache(2);
}

### END
########################################################################

1;

__END__

=head1 NAME

ModisDownload - Perl extension for downloading MODIS satellite data

=head1 SYNOPSIS

  use ModisDownload;

  # to initialize the cache files in ~/.cache/ModisDownload
  initCache();

  # reinitialize the cache
  refreshCache();

  # load the cache
  loadCache();

  # print available versions of a certain product
  print "Versions of MOD17A2:";
  print " $_" foreach (getVersions("MOD17A2"));
  print "\n";

  # is the data in one file for the whole world?
  print "nonexisting: ".isGlobal("nonexisting")."\n"; # this does not exist
  print "MOD17A2.005: ".isGlobal("MOD17A2.005")."\n";
  print "MCD12C1.051: ".isGlobal("MCD12C1.051")."\n";

  # print a list of URLs (can be used for wget)
  my @URLs1 = getURLs("MOD17A2", ["2002.01.01", "2002.01.10"], [29, 30], [12]);
  print "$_\n" foreach (@URLs1);
  my @URLs2 = getURLs("MCD12C1", "051", ["2005.01.01", "2005.01.01"]);
  print "$_\n" foreach (@URLs2);

  # download the list to the current directory
  modisDownload(\@URLs1);
  system("mv MOD17A2.A2002001.h29v12.005.2007114184339.hdf MOD17A2.A2002001.h29v12.005.2007114184339.hdf.bak");
  system("head -c 1051980 MOD17A2.A2002001.h29v12.005.2007114184339.hdf.bak > MOD17A2.A2002001.h29v12.005.2007114184339.hdf");
  # output some info
  modisDownload(\@URLs1, ".", 1);

  # download the list and be verbose
  # LARGE FILE! (1.3 GB)
  modisDownload(\@URLs2, ".", 1);
  # download the list to the current directory and force a reload of already existing files
  modisDownload(\@URLs2, ".", 1, 1);

=head1 DESCRIPTION

This module creates a list of URLs for downloading MODIS satellite data
in standard hdf format. It loads metadata of all available products and
their versions to three cache files under ~/.cache/ModisDownload/, which
are read and used to create a list of desired data files for download.
ThisURL list can be printed to STDOUT and used to download the data via
wget.

You need to supply the function getURLs with 

=over 1

=item product ID

the desired product key,

=item version

the version (optionally),

=item dates

the date(s): either one exact date or start and end in the format
"YYYY.MM.DD" as an anonymous array.

=item h

anonymous arrays for the h of the sinusoidal grid, if it is not a global
dataset.

=item v

anonymous arrays for the v of the sinusoidal grid, if it is not a global
dataset.

=back

If not supplied, the default version number is "005" if available,
otherwise the highest available version.


=head1 FUNCTIONS

=head2 initCache

=for intialize cached server data

=for usage

  my $retval = initCache();

This function initializes the cache files, which are used on every
subsequent usage. The Cache consists of directory information and if
the datasets are in one file forthe whole world or on the sinusoidal
grid. This speeds up any subsequent usage of the module.

=head2 loadCache

=for load the cached server data

=for usage

  my $retval = loadCache();

This function loads the stored cache data to memory.

=head2 refreshCache

=for refresh the cached data

=for usage

  my $retval = refreshCache();

This function dowloads the directory structure again and writes new cache
files.

=head2 getVersions

=for retrieves the available product versions fron the cached data

=for usage

  my @versions = getVersions($product);

This functions returns the available versions for a certain MODIS product.

=head2 isGlobal

=for check if a product is global or sinusoidal

=for usage

  my $retval = isGlobal($prod);

Here the version string needs to be appended to the MODIS product sepparated
by a dot (see example in the SYNOPSIS section).

=head2 getURLs

=for return a list of URLs to be downloaded.

=for usage
  my @URLs = getURLs($prod, $version, [@dates], [@h], [@v]);

after initializing the cache, this function can be used to return a list
offiles, which can be downloaded p.e. via wget or your own download perl
module.

ATTENTION: The "dates" "h" and "v" arguments only the maximum and minimum 
values are evaluated. So if you want to download data for Alaska and Australia,
this should be done in two separate getURLs calls. Otherwise almost the whole
world will be downloaded and this can very quickly results in several hundreds
of Gigabytes to be downloaded.

For examples see the SYNOPSIS section.

=head2 modisDownload

=for downloads file(s)

=for usage
  modisDownload({\@,$}URLs, [{\@,$}destination], [$verbose], [$forceReload]);

continuous download of a list (as array reference) or a single file to a list
(as array reference) of destination files or a destination directory. If a third
argument is supplied it will be printed, what is downloaded and if a forth 
argument is supplied (no matter what) allready existing files will be 
overwritten. Otherwise they will be appended with the offset of the already
existing file length.

ATTENTION: Not yet checked for all possible stupid combinations of URLs
and destination atomic or array combinations.

=head1 TODO

=over 4

=item Wrinting a test.pl file

=item So far the functions issue a warning or return a negative integer,
if something unforseen happens. This needs to be improved.

=item Test the module on other operating systems.

=item Use Carp where useful

=item make_path dies if the path can not be created, catch it or use something else 
for error handling

=item rewrite setCache to store the data in memory only instead of writing the cached
datato disk

=back

=head1 SEE ALSO

Description of terrestrial MODIS products can be found on https://lpdaac.usgs.gov/.
The work was inspired by ModisDownload.R (http://r-gis.net/?q=ModisDownload), which
sadly did so far not support continued download if the connection was interrupted,
which happened quiet often for me.

=head1 AUTHOR

Joerg Steinkamp, joergsteinkamp@yahoo.de

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2015 by Joerg Steinkamp

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.20.1 or,
at your option, any later version of Perl 5 you may have available.


=cut
