
use strict;
use warnings;

use 5.008;

use ExtUtils::MakeMaker 6.30;



my %WriteMakefileArgs = (
  "ABSTRACT" => "Business::CPI's PayPal driver",
  "AUTHOR" => "Andr\x{e9} Walker <andre\@andrewalker.net>",
  "BUILD_REQUIRES" => {},
  "CONFIGURE_REQUIRES" => {
    "ExtUtils::MakeMaker" => "6.30"
  },
  "DISTNAME" => "Business-CPI-Gateway-PayPal",
  "EXE_FILES" => [],
  "LICENSE" => "perl",
  "NAME" => "Business::CPI::Gateway::PayPal",
  "PREREQ_PM" => {
    "Business::CPI" => "0.909",
    "Business::PayPal::NVP" => 0,
    "DateTime" => 0,
    "DateTime::Format::Strptime" => 0,
    "LWP::UserAgent" => 0,
    "Moo" => "1.0"
  },
  "TEST_REQUIRES" => {},
  "VERSION" => "0.903",
  "test" => {
    "TESTS" => "t/*.t"
  }
);


my %FallbackPrereqs = (
  "Business::CPI" => "0.909",
  "Business::PayPal::NVP" => 0,
  "DateTime" => 0,
  "DateTime::Format::Strptime" => 0,
  "LWP::UserAgent" => 0,
  "Moo" => "1.0"
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.63_03) } ) {
  delete $WriteMakefileArgs{TEST_REQUIRES};
  delete $WriteMakefileArgs{BUILD_REQUIRES};
  $WriteMakefileArgs{PREREQ_PM} = \%FallbackPrereqs;
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);



