package DateTime::Format::Naturalish;
# ABSTRACT: Parse human date/time

use 5.010;
use strict;
use warnings;
use locale;

use Class::Inspector;
use DateTime;

=for Pod::Coverage ^a_ ^adat_ ^adur_ ^aset_

=cut

sub new {
    my ($class) = @_;
    my $self = bless {}, $class;
    $self->_compile_patterns;
    $self;
}

sub _compile_patterns {
    my ($self) = @_;

    # put stuffs in package variables, to share between objects.
    my $class = ref($self);

    no strict 'refs';
    my $pat     = ${$class . '::pat'};
    return if $pat;
    my $dat_pat = ${$class . '::dat_pat'};
    my $dur_pat = ${$class . '::dur_pat'};
    my $set_pat = ${$class . '::set_pat'};

    my $methods = Class::Inspector->methods($class);

    $pat     = {};
    for (grep { /^p_/ } @$methods) {
        my $k = $_; $k =~ s/^p_//;
        $pat->{$k} = $self->$_;
    }
    ${$class . '::pat'} = $pat;

    $dat_pat = join ("|",
                     map { "(?<$_>".$self->$_.")" }
                         grep { /^pdat_/ } @$methods);
    die "BUG: No datetime patterns defined" unless $dat_pat;
    $dat_pat = qr/$dat_pat/;
    ${$class . '::dat_pat'} = $dat_pat;

    $dur_pat = join ("|",
                     map { "(?<$_>".$self->$_.")" }
                         grep { /^pdur_/ } @$methods);
    die "BUG: No datetime duration patterns defined" unless $dur_pat;
    $dur_pat = qr/$dur_pat/;
    ${$class . '::dur_pat'} = $dur_pat;

    $set_pat = join ("|",
                     map { "(?<$_>".$self->$_.")" }
                         grep { /^pset_/ } @$methods);
    die "BUG: No datetime recurrence patterns defined" unless $dur_pat;
    $set_pat = qr/$set_pat/;
    ${$class . '::set_pat'} = $set_pat;
}

=head2 $parser->preprocess(STR) => STR

Preprocess string before being parsed. The default implementation trims the
string and converts it to lowercase using lc().

=cut

sub preprocess {
    my ($self, $str) = @_;
    for ($str) { s/\A\s+//s; s/\s+\z//s }
    lc($str);
}

sub parse_datetime {
    my ($self, $str) = @_;
    my $class = ref($self);
    no strict 'refs';

    $str = $self->preprocess($str);
    return unless $str =~ ${$class . "::dat_pat"};
    my %m = %+;
    my @pat = grep {/^pdat_/} keys %m;
    @pat or die "BUG: Matched but no pdat_* pattern captured";
    my $method = $pat[0];
    $method =~ s/^pdat_/adat_/;
    $self->can($method) or die "BUG: No action method $method defined";
    print "Calling method $method\n";
    $self->$method(\%m);
}

sub parse_datetime_duration {
    die "Not implemented yet";
}

sub parse_datetime_recurrence {
    die "Not implemented yet";
}

sub format_datetime {
    die "Not implemented yet";
}

sub format_datetime_duration {
    die "Not implemented yet";
}

sub format_datetime_recurrence {
    die "Not implemented yet";
}

=head2 $parser->parse_num(STR) => NUM

Parse number matched by p_num().

=cut

sub parse_num {
    my ($self, $str) = @_;
    $str+0;
}

=head1 COMMON PATTERN METHODS

These methods are prefixed with "p_".

=head2 wsep

Regex for matching word separator. The default is \s+. You might want to
override this e.g. for Chinese where words are not separated by whitespace.

=cut

sub p_wsep { qr/\s+/ }

=head2 words

Regex for matching words. Default is:

 \w+ ($p_wsep \w+)*

Normally you do not need to override this.

=cut

sub p_words {
    my $self = shift;
    my $wsep = $self->p_wsep;
    qr/\w+(?:$wsep \w+)*/x;
}

=head2 num

Regex for matching number. The default accepts integer and decimal numbers. If
you override this, make sure you also adjust parse_num().

=cut

# XXX support thousand operators
# XXX support verbage (e.g. "twenty two" for 22)
sub p_num {
    qr/(?:\d+\.?|\d*\.\d+)/x;
}

=head1 DATETIME PATTERN METHODS

All the methods are prefixed by "pdat_".

=head2 now

English example(s): now

=cut

sub adat_now {
    my ($self, $match) = @_;
    DateTime->now;
}

=head2 x_ago

English example(s): 1 hour ago, 2 days 14 minutes 120 seconds ago

=cut

sub adat_x_ago {
    my ($self, $match) = @_;
}

=head2 x_from_now

Just like x_ago, but for describing periods in the future.

=cut

sub adat_x_from_now {
    my ($self, $str) = @_;
}

1;
__END__

# if today=wed, this_weekday(tue)= H-8 (if a=-1) / H-1 (if a=0) / H+6 (if a=1),
# this_weekend(wed)=H-7 (if b=-1) / H (if b=0) / H+7 (if b=1),
# this_weekday(thu)=H-6 (if c=-1) / H+1 (if c=0) / H+8 (if c=7)

sub last_weekday_param_a { -1 }
sub last_weekday_param_b { -1 }
sub last_weekday_param_c { -1 }

sub this_weekday_param_a {  0 }
sub this_weekday_param_b {  0 }
sub this_weekday_param_c {  0 }

sub next_weekday_param_a {  1 }
sub next_weekday_param_b {  1 }
sub next_weekday_param_c {  1 }

sub calc_weekday {
    my ($self, $dt, $target_dow, $a, $b, $c) = @_;
    my $cur_dow = $dt->day_of_week;
    my $n = $target_dow - $cur_dow;
    if ($target_dow < $cur_dow) {
        $n += ($a==-1 ? -7 : $a== 0 ?  0 : 7);
    } elsif ($target_dow == $cur_dow) {
        $n += ($b==-1 ? -7 : $b== 0 ?  0 : 7);
    } else {
        $n += ($c==-1 ? -7 : $c== 0 ?  0 : 7);
    }
    $dt->add(days => $n);
}

sub calc_last_weekday {
    my ($self, $dt, $target_dow, $a, $b, $c) = @_;
    $a //= $self->last_weekday_param_a;
    $a //= $self->last_weekday_param_b;
    $a //= $self->last_weekday_param_c;
    $self->calc_weekday($dt, $target_dow, $a, $b, $c);
}

sub calc_this_weekday {
    my ($self, $dt, $target_dow, $a, $b, $c) = @_;
    $a //= $self->this_weekday_param_a;
    $a //= $self->this_weekday_param_b;
    $a //= $self->this_weekday_param_c;
    $self->calc_weekday($dt, $target_dow, $a, $b, $c);
}

sub calc_next_weekday {
    my ($self, $dt, $target_dow, $a, $b, $c) = @_;
    $a //= $self->next_weekday_param_a;
    $a //= $self->next_weekday_param_b;
    $a //= $self->next_weekday_param_c;
    $self->calc_weekday($dt, $target_dow, $a, $b, $c);
}



sub t_WEEKDAY {
    my ($self) = @_;
    state $data = do {
        my $tmp = join "|", keys %{ $self->h_WEEKDAY };
        qr/(?:$tmp)/;
    };
}

sub t_MONTH {
    my ($self) = @_;
    state $data = do {
        my $tmp = join "|", keys %{ $self->h_MONTH };
        qr/(?:$tmp)/;
    };
}

# should return ambiguous when it should: e.g. if today if monday, "tuesday"
# might be pretty clear (although it might be ambiguous too). but "friday" might
# be ambiguous.

sub p_WEEKDAY { "t_WEEKDAY" }

sub a_WEEKDAY {
    my ($self, $dt, $match) = @_;
    $self->calc_weekday($dt, $self->h_WEEKDAY->{ $match->{WEEKDAY} },
                        0, 0, 0);
}

sub p_THIS_WEEKDAY { "<THIS> <L_WEEKDAY>" }

sub a_THIS_WEEKDAY {
    my ($self, $dt, $match) = @_;
    $self->calc_this_weekday_B($dt, $self->h_WEEKDAY->{ $match->{WEEKDAY} });
}

# 4th day last week
sub a_ORDINAL_DAY_LASTNEXT_WEEK {
    my ($self, $dt, $match) = @_;
    my $n = get_number($match->{ORDINAL});
    #...
    calculate_;
}

#sub p_THIS_WEEKEND { "<THIS> <WEEKEND>" }
# NEXT/LAST_WEEKEND
# THIS/NEXT/LAST_WEEKEND
# ...

# recurrence
p_EVERY_DOW;
p_EVERY_WEEKEND;
p_EVERY_DAY;
p_EVERY_OTHER_DAY;
p_EVERY_N_DAY;
P_EVERY_WEEK;
p_EVERY_OTHER_WEEK;
p_EVERY_N_WEEK;
p_WEEKLY;
p_BIWEEKLY;
p_EVERY_MONTH;
p_EVERY_OTHER_MONTH;
p_EVERY_N_MONTH;
p_MONTHLY;
p_BIMONTHLY;
p_QUARTERLY;
#p_EVERY_SEMESTER;
#p_EVERY_OTHER_SEMESTER;
#p_EVERY_N_SEMESTER;
p_EVERY_YEAR;
p_EVERY_OTHER_YEAR;
p_EVERY_N_YEAR;
p_YEARLY = p_ANNUALLY;
p_BIANNUALLY = p_BIENNIALLY;
p_TRENNIALLY = p_TRIANNUALLY?;
p_EVERY_DECADE;
p_EVERY_OTHER_DECADE;
p_EVERY_N_DECADE;
p_EVERY_CENTURY;
p_EVERY_OTHER_CENTURY;
p_EVERY_N_CENTURY;
p_EVERY_MILLENIUM;
p_EVERY_OTHER_MILLENIUM;
p_EVERY_N_MILLENIUM;

p_PERIODOFDAY -> morning; afternoon; ...
p_THIS_PERIODOFDAY -> this morning; this evening;
p_;

1;
__END__

=head1 SYNOPSIS

 use DateTime;
 use DateTime::Format::Naturalish;

 my $parser = DateTime::Format::Naturalish->new();
 my $dt = $parser->parse_datetime("2 hours 13 minutes from now");


=head1 DESCRIPTION

There are already some other DateTime human language parsers on CPAN, e.g.
L<DateTime::Format::Natural>. This module is yet another implementation of such,
designed to make it easy to add new human languages.


=head1 HOW IT WORKS

Parsing a date string is done by matching it against a bunch of regex patterns.
Parsing succeeds if there is at least one pattern matches. Parsing fails if no
pattern matches.

You provide patterns in p_*() methods (or pd_*(), for parsing duration).
Example:

 # in DateTime::Format::Naturalish::en
 sub p_now       { qr/(?:now)/ }

 # in DateTime::Format::Naturalish::id
 sub p_yesterday { qr/(?:kemarin)/ }

Make sure you put non-capturing group around the pattern, so it can safely be
composed into other larger patterns.

All p_*() methods will be combined into a single regex, which is then matched
with text. The same is done with all pd_*() methods.

When a pattern matches the text, an associated a_*() action method will be run
to set the resulting DateTime (or DateTime::Duration) object. For example:

 sub a_yesterday {
     my $self = shift;
     my $dt = $self->result;
     $dt->add(days => -1);
 }


=head1 ADDING A NEW HUMAN LANGUAGE

To add a new language, subclass this module and override the p_*() and pd_*()
methods as needed. The a_*() methods should mostly be reusable.

See L<DateTime::Format::Naturalish::id> or
L<DateTime::Format::Naturalish::zh_CN> for examples.


=head1 SEE ALSO

L<DateTime::Format::Natural>

=cut

$RE{year} = qr/^
    %data_conversion = (
        last_this_next    => { lalu => -1, ini => 0, depan => 1 },
        yes_today_tom     => { "kemarin lusa" => -2,
                               kemarin => -1, kmrn => -1,
                               "hari ini" => 0,
                               besok => 1, esok => 1,
                               lusa => 2, "besok lusa" => 2, "esok lusa", => 2,
                           },
        noon_midnight     => { "tengah hari" => 12, "tengah malam" => 0 },
        morn_aftern_even  => { pagi => 0, siang => 1, sore => 2, malam => 3 },
        before_after_from => { sebelum => -1, sesudah => 1, dari => 1 },
    );

    %data_helpers = (
        normalize   => sub { ${$_[0]} = ucfirst lc ${$_[0]} },
    );

    %data_duration = (
        for => sub {
            my ($date_strings) = @_;
            return (@$date_strings == 1
                && $date_strings->[0] =~ /^selama \s+/ix);
        },
        #XXX
        first_to_last => sub {
            my ($date_strings) = @_;
            return (@$date_strings == 2
                && $date_strings->[1] =~ /^pertama$/i
                && $date_strings->[1] =~ /^terakhir \s+/ix);
        },
        date_time_to_time => sub {
            my ($date_strings) = @_;

            my $date = qr!(?:\d{1,4}) (?:[-./]\d{1,4}){0,2}!x;
            my $time = qr!(?:\d{1,2}) (?:[:.]\d{2}){0,2}!x;

            return (@$date_strings == 2
                && $date_strings->[0] =~ /^$date \s+ $time$/x
                && $date_strings->[1] =~ /^$time$/);
        },
    );

    %data_aliases = (
        words => {
            #EN#tues  => 'tue',
            #EN#thurs => 'thu',
        },
        tokens => {
            #EN#mins => 'minutes',
            '@'  => 'pada',
        },
        short => {
            dtk => 'detik',
            men => 'menit',
            mnt => 'menit',
            j   => 'jam',
            hr  => 'hari',
            h   => 'hari',
            #min => 'minggu',
            mgg => 'minggu',
            bul => 'bulan',
            bln => 'bulan',
            bl  => 'bulan',
            th  => 'tahun',
            thn => 'tahun',
        },
    );
}

%extended_checks = (
);

PERIODOFDAY_AT_H -> tonight at 8 pm;
 yesterday at 10pm;
RELATIVEDAY_PERIODOFDAY -> yesterday evening;
AT_H -> at 8 o'clock;
AT_HM -> at 10:20pm;
XXX_AGO
XXX_FUTURE
MONTH
MONTH_DAY;
MONTH_DAY_AT;
MONTH_DAY_YEAR;

1;
__END__

=head1 DESCRIPTION

C<DateTime::Format::Natural::Lang::ID> provides the Indonesian specific grammar
and variables. This class is loaded if the user specifies the Indonesian
language.

=head1 EXAMPLES

Below are some examples of human readable date/time input in Indonesian (be
aware that the parser does not distinguish between lower/upper case):

=head2 Simple

 sekarang (skr, skrg, skrng, saat ini)
 kemarin (krmn)
 hari ini
 besok (esok)
 pagi
 siang
 sore
 # malam (mlm)
 tengah hari
 tengah malam
 kemarin tengah siang
 kemarin tengah malam
 hari ini tengah siang
 hari ini tengah malam
 tomorrow at noon
 tomorrow at midnight
 this morning
 this afternoon
 this evening
 yesterday morning
 yesterday afternoon
 yesterday evening
 today morning
 today afternoon
 today evening
 tomorrow morning
 tomorrow afternoon
 tomorrow evening
 6:00 yesterday
 6:00 today
 6:00 tomorrow
 5am yesterday
 5am today
 5am tomorrow
 4pm yesterday
 4pm today
 4pm tomorrow
 last second
 this second
 next second
 last minute
 this minute
 next minute
 last hour
 this hour
 next hour
 last day
 this day
 next day
 last week
 this week
 next week
 last month
 this month
 next month
 last year
 this year
 next year
 last friday
 this friday
 next friday
 tuesday last week
 tuesday this week
 tuesday next week
 last week wednesday
 this week wednesday
 next week wednesday
 10 seconds ago
 10 minutes ago
 10 hours ago
 10 days ago
 10 weeks ago
 10 months ago
 10 years ago
 in 5 seconds
 in 5 minutes
 in 5 hours
 in 5 days
 in 5 weeks
 in 5 months
 in 5 years
 saturday
 sunday 11:00
 yesterday at 4:00
 today at 4:00
 tomorrow at 4:00
 yesterday at 6:45am
 today at 6:45am
 tomorrow at 6:45am
 yesterday at 6:45pm
 today at 6:45pm
 tomorrow at 6:45pm
 yesterday at 2:32 AM
 today at 2:32 AM
 tomorrow at 2:32 AM
 yesterday at 2:32 PM
 today at 2:32 PM
 tomorrow at 2:32 PM
 yesterday 02:32
 today 02:32
 tomorrow 02:32
 yesterday 2:32am
 today 2:32am
 tomorrow 2:32am
 yesterday 2:32pm
 today 2:32pm
 tomorrow 2:32pm
 wednesday at 14:30
 wednesday at 02:30am
 wednesday at 02:30pm
 wednesday 14:30
 wednesday 02:30am
 wednesday 02:30pm
 friday 03:00 am
 friday 03:00 pm
 sunday at 05:00 am
 sunday at 05:00 pm
 2nd monday
 100th day
 4th february
 november 3rd
 last june
 next october
 6 am
 5am
 5:30am
 8 pm
 4pm
 4:20pm
 06:56:06 am
 06:56:06 pm
 mon 2:35
 1:00 sun
 1am sun
 1pm sun
 1:00 on sun
 1am on sun
 1pm on sun
 12:14 PM
 12:14 AM

=head2 Complex

 yesterday 7 seconds ago
 yesterday 7 minutes ago
 yesterday 7 hours ago
 yesterday 7 days ago
 yesterday 7 weeks ago
 yesterday 7 months ago
 yesterday 7 years ago
 tomorrow 3 seconds ago
 tomorrow 3 minutes ago
 tomorrow 3 hours ago
 tomorrow 3 days ago
 tomorrow 3 weeks ago
 tomorrow 3 months ago
 tomorrow 3 years ago
 2 seconds before now
 2 minutes before now
 2 hours before now
 2 days before now
 2 weeks before now
 2 months before now
 2 years before now
 4 seconds from now
 4 minutes from now
 4 hours from now
 4 days from now
 4 weeks from now
 4 months from now
 4 years from now
 6 in the morning
 4 in the afternoon
 9 in the evening
 monday 6 in the morning
 monday 4 in the afternoon
 monday 9 in the evening
 last sunday at 21:45
 monday last week
 6th day last week
 6th day this week
 6th day next week
 12th day last month
 12th day this month
 12th day next month
 1st day last year
 1st day this year
 1st day next year
 1st tuesday last november
 1st tuesday this november
 1st tuesday next november
 11 january next year
 11 january this year
 11 january last year
 6 hours before yesterday
 6 hours before tomorrow
 3 hours after yesterday
 3 hours after tomorrow
 10 hours before noon
 10 hours before midnight
 5 hours after noon
 5 hours after midnight
 noon last friday
 midnight last friday
 noon this friday
 midnight this friday
 noon next friday
 midnight next friday
 last friday at 20:00
 this friday at 20:00
 next friday at 20:00
 1:00 last friday
 1:00 this friday
 1:00 next friday
 1am last friday
 1am this friday
 1am next friday
 1pm last friday
 1pm this friday
 1pm next friday
 yesterday at 13:00
 today at 13:00
 tomorrow at 13
 2nd friday in august
 3rd wednesday in november
 tomorrow 1 year ago
 saturday 3 months ago at 17:00
 saturday 3 months ago at 5:00am
 saturday 3 months ago at 5:00pm
 11 january 2 years ago
 4th day last week
 8th month last year
 8th month this year
 8th month next year
 6 mondays from now
 fri 3 months ago at 5am
 wednesday 1 month ago at 8pm
 final thursday in april
 last thursday in april

=head2 Timespans

 monday to friday
 1 April to 31 August
 1999-12-31 to tomorrow
 now to 2010-01-01
 2009-03-10 9:00 to 11:00
 1/3 to 2/3
 2/3 to in 1 week
 3/3 21:00 to in 5 days
 first day of 2009 to last day of 2009
 first day of may to last day of may
 first to last day of 2008
 first to last day of september
 for 4 seconds
 for 4 minutes
 for 4 hours
 for 4 days
 for 4 weeks
 for 4 months
 for 4 years

=head2 Specific

 march
 january 11
 11 january
 dec 25
 feb 28 3:00
 feb 28 3am
 feb 28 3pm
 may 27th
 2005
 march 1st 2009
 October 2006
 february 14, 2004
 jan 3 2010
 3 jan 2000
 27/5/1979
 1/3
 1/3 16:00
 4:00
 17:00
 3:20:00
 -5min
 +2d

=head2 Aliases

 5 mins ago
 yesterday @ noon
 tues this week
 final thurs in sep
 tues
 thurs


