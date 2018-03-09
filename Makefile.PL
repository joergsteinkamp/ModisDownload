use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
  NAME              => 'WebService::MODIS',
  VERSION_FROM      => 'lib/WebService/MODIS.pm', # finds $VERSION, requires EU::MM from perl >= 5.5
  MIN_PERL_VERSION => '5.6.0', # according to perlver (Perl::MinimumVersion)
  PREREQ_PM         => {
    'Carp'           => 0,
    'URI'            => 0,
    'LWP::UserAgent' => 0,
    'HTTP::Cookies'  => 0,
    'Net::Netrc'     => 0,
    'File::HomeDir'  => 0,
    'File::Path'     => 0,
    'File::Basename' => 0,
    'Date::Simple'   => 0,
    'List::Util'     => 1.33,
  }, # e.g., Module::Name => 1.1

  TEST_REQUIRES => {
    'LWP::Online'    => 0,
  },

  ABSTRACT_FROM     => 'lib/WebService/MODIS.pm', # retrieve abstract from module
  AUTHOR            => 'Joerg Steinkamp <joergsteinkamp@yahoo.de>',
  LICENSE           => 'gpl_3',
  #Value must be from legacy list of licenses here
  #http://search.cpan.org/perldoc?Module%3A%3ABuild%3A%3AAPI

  META_MERGE => {
    'meta-spec' => { version => 2 },
    resources => {
      repository => {
        type => 'git',
        url  => 'https://github.com/joergsteinkamp/ModisDownload.git',
        web  => 'https://github.com/joergsteinkamp/ModisDownload',
      },
    },
  },
);
