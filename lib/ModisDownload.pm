package ModisDownload;

use 5.020001;
use strict;
use warnings;
use LWP::UserAgent;
use File::Path qw(make_path);
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
our @EXPORT = qw(loadCache initCache refreshCache getVersions getURLs isGlobal);

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

########################################################################
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
    make_path($CacheDir) || warn("Could not create cache dir ('$CacheDir'): $!\n");
  }

  my $fhd;

  ### Set up the MODIS products cache
  my %lookupTable = getAvailData();
  my $N = keys(%lookupTable);

  open($fhd, ">", "$CacheDir/$ModisCacheFile") || 
    warn("cannot open \"$CacheDir/$ModisCacheFile\" for writing: $!\n");

  for (keys %lookupTable) {
    print  $fhd "'$_' => '$lookupTable{$_}',\n";
  }
  close($fhd) || warn "close \"$CacheDir/$ModisCacheFile\" failed: $!";
  %MODIS = do "$CacheDir/$ModisCacheFile";

  ### Set up the MODIS dates cache
  %lookupTable = getAvailDates(\%MODIS);
  $N = keys(%lookupTable);

  open($fhd, ">", "$CacheDir/$ModisDatesCacheFile") ||
    warn("cannot open \"$CacheDir/$ModisDatesCacheFile\" for writing: $!\n");

  for (keys %lookupTable) {
    print  $fhd "'$_' => $lookupTable{$_},\n";
  }
  close($fhd) || warn "close \"$CacheDir/$ModisDatesCacheFile\" failed: $!";
  %MODISDates = do "$CacheDir/$ModisDatesCacheFile";

  ### Set up the MODIS global check cache
  open($fhd, ">", "$CacheDir/$ModisGlobalCacheFile") ||
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
          warn(sprintf("Missing file for %s @ %s.\n", $pat, $date->format("%Y.%m.%d")));
        } else { 
          # check for duplicate files here and choose the latest one
          warn(sprintf("%i files for %s @ %s, choosing the newest.\n", $nNewURLs, $pat, $date->format("%Y.%m.%d")));
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
  }
  return(@URLs);
}

########################################################################
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
### Exported functions

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

### END: Functions to set up and refresh the cached data
########################################################################


1;

__END__
# Below is stub documentation for your module. You'd better edit it!

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
  print "$_\n" foreach (getVersions("MOD17A2"));

  # is the data in one file for the whole world?
  print isGlobal("MOD17A3.005");
  print "$_\n";
  print isGlobal("MCD12C1.051");
  print "$_\n";

  # print a list of URLs
  print "$_\n" foreach (getURLs("MOD17A3", ["2000.01.01", "2003.01.01"], [29, 30], [12]));
  print "$_\n" foreach (getURLs("MCD12C1", "051", ["2005.01.01", "2006.01.01"]));

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

=head1 TODO

=over 4

=item Wrinting a test.pl file

=item So far the functions issue a warning or return a negative integer,
if something unforseen happens. This needs to be improved.

=item Test the module on other operating systems.

=item Use Carp where useful



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
