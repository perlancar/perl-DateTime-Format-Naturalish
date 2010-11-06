package DateTime::Format::Humania;
# ABSTRACT: Parse human date/time

=head1 SYNOPSIS

 use DateTime;
 use DateTime::Format::Humania;

 my $parser = DateTime::Format::Humania->new();
 my $dt = $parser->parse_datetime("2 hours 13 minutes from now");

=head1 DESCRIPTION

There are already some other DateTime human language parsers on CPAN, e.g.
L<DateTime::Format::Natural>. This module is yet another implementation of such,
designed to make it easy to add new human languages.

=head1 HOW IT WORKS

Parsing a date string is done by matching it against a bunch of patterns. Parsing
succeeds if there is at least one pattern matches. Parsing fails if no pattern
matches.

A pattern is basically a regex. You provide them in p_*() methods. Example:

 # in DateTime::Format::Humania::EN
 sub p_now       { { pattern => qr/(?:now)/ }

 # in DateTime::Format::Humania::ID
 sub p_yesterday { qr/(?:kemarin)/ }

When a pattern matches the text, an associated a_*() action method will be run.
For example:

 sub a_YESTERDAY { my ($self, $dt) = @_; $dt->add(days => -1) }

The action method will be given a DateTime object which was initially created
using DateTime->now().

A pattern can be composed of tokens and other patterns:

 # in EN
 sub p_LAST_WEEKDAY { "<LAST> <WEEKDAY>" }
 sub t_LAST { "last" }

 # in ID (in Indonesian, order is reversed, we usually say 'saturday next')
 sub p_NEXT_WEEKDAY { "<WEEKDAY> <NEXT>" }
 sub t_NEXT { ["berikutnya", "depan"] }

They will also be converted into a regex, e.g. in EN (note the named captures):

 qr/(?<NEXT>(?:last)) (?<WEEKDAY>(?:monday|mon|tuesday|tue|...))/

=head1 ADDING A NEW HUMAN LANGUAGE

To add a new language, subclass this module, which already contains many patterns
(though some might contain Englishisms). You usually then alter a few p_*()
methods, as well as provide some translations for some text (like weekday and
month names in t_*() methods). The point is that most of the action methods
should be reusable.

Of course you can add new patterns along with their actions, though try to think
more generically and see if your new pattern is also applicable to English/the
base class.

If you want to remove some patterns because it is not used in your language,
override the associated p_*() method and return undef.

For more details, view the source code to existing translations, like
L<DateTime::Format::Humania::ID>.

=cut

use 5.010;
use strict;
use warnings;

use Any::Moose;
use DateTime;

has all_patterns_re => (is => 'rw');

sub BUILD {
    my ($self, %args) = @_;
    $self->prepare_patterns unless $self->{all_patterns_re};
}

sub prepare_patterns {
    my ($self) = @_;

    $self->{patterns} = [];
}

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

# combine all pattern res into a single one, for matching strings

sub compile_single_big_re {
    my ($self) = @_;
    my $re = join(
        "|",
        sort {length($b) <=> length($a)}
            map { $_->[0] } @{ $self->{patterns} }
        );
    $self->{single_big_re} = qr/\A$re\z/;
}

sub preprocess {
    my ($self, $str) = @_;
    for ($str) { s/\A\s+//s; s/\s+\z//s; }
    lc($str);
}

sub parse_datetime {
    my ($self, $str) = @_;
    my $re = $self->{single_big_re};

    $str = $self->preprocess($str);

    # parsing boils down to just matching string against single big re, and then
    # running the matching pattern's subroutine.

    if ($str =~ $re) {
        my $dt = DateTime->now;
        for my $p (@{ $self->{patterns} }) {
            next unless $str =~ $p->[0];
            $p->[1]->($dt);
        }
        return $dt;
    } else {
        return;
    }
}

sub parse_datetime_duration {
    die "Not implemented yet";
}

sub format_datetime {
    die "Not implemented yet";
}

sub format_datetime_duration {
    die "Not implemented yet";
}



### tokens, patterns, and actions


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

sub p_

no Any::Moose;
1;
__END__
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

# <keyword> => [
#    [ <PERL TYPE DECLARATION>, ... ], ---------------------> declares how the tokens will be evaluated
#    [
#      { <token index> => <token value>, ... }, ------------> declares the index <-> value map
#      [ [ <index(es) of token(s) to be passed> ], ... ], --> declares which tokens will be passed to the extended check(s)
#      [ <subroutine(s) for extended check(s)>, ... ], -----> declares the extended check(s)
#      [ [ <index(es) of token(s) to be passed> ], ... ], --> declares which tokens will be passed to the worker method(s)
#      [ { <additional options to be passed> }, ... ], -----> declares additional options
#      [ <name of method to dispatch to>, ... ], -----------> declares the worker method(s)
#      { <shared option>, ... }, ---------------------------> declares shared options (post-processed)
#    ],

%grammar = (
    now => [
       [ 'SCALAR' ],
       [
         { 0 => qr/^(?:sekarang|skrng|skrg|skr|saat ini)$/i },
         [],
         [],
         [ [] ],
         [ {} ],
         [ '_no_op' ],
         {},
       ],
    ],
    day => [
       [ 'REGEXP' ],
       [
         { 0 => qr/^(hari ini)$/i },
         [],
         [],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
         ],
         [ { unit => 'day' } ],
         [ '_unit_variant' ],
         { truncate_to => 'day' },
       ],
       [
         { 0 => qr/^(yesterday)$/i },
         [],
         [],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
         ],
         [ { unit => 'day' } ],
         [ '_unit_variant' ],
         { truncate_to => 'day' },
       ],
       [
         { 0 => qr/^(tomorrow)$/i },
         [],
         [],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
         ],
         [ { unit => 'day' } ],
         [ '_unit_variant' ],
         { truncate_to => 'day' },
       ],
    ],
    dayframe => [
       [ 'REGEXP' ],
       [
         { 0 => qr/^(morning)$/i },
         [],
         [],
         [
           [
             { 0 => [ $flag{morn_aftern_even} ] },
           ],
         ],
         [ {} ],
         [ '_daytime_variant' ],
         {},
       ],
       [
         { 0 => qr/^(afternoon)$/i },
         [],
         [],
         [
           [
             { 0 => [ $flag{morn_aftern_even} ] },
           ],
         ],
         [ {} ],
         [ '_daytime_variant' ],
         {},
       ],
       [
         { 0 => qr/^(evening)$/i },
         [],
         [],
         [
           [
             { 0 => [ $flag{morn_aftern_even} ] },
           ],
         ],
         [ {} ],
         [ '_daytime_variant' ],
         {},
       ]
    ],
    daytime_noon_midnight => [
       [ 'REGEXP' ],
       [
         { 0 => qr/^(noon)$/i },
         [],
         [],
         [
           [
             { 0 => [ $flag{noon_midnight} ] },
           ],
         ],
         [ {} ],
         [ '_daytime' ],
         {},
       ],
       [
         { 0 => qr/^(midnight)$/i },
         [],
         [],
         [
           [
             { 0 => [ $flag{noon_midnight} ] },
           ]
         ],
         [ {} ],
         [ '_daytime' ],
         {},
       ],
    ],
    daytime_noon_midnight_at => [
       [ 'REGEXP', 'SCALAR', 'REGEXP' ],
       [
         { 0 => qr/^(yesterday)$/i, 1 => 'at', 2 => qr/^(noon)$/i },
         [],
         [],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 2 => [ $flag{noon_midnight} ] },
           ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_daytime' ],
         {},
       ],
       [
         { 0 => qr/^(yesterday)$/i, 1 => 'at', 2 => qr/^(midnight)$/i },
         [],
         [],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 2 => [ $flag{noon_midnight} ] },
           ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_daytime' ],
         {},
       ],
       [
         { 0 => qr/^(today)$/i, 1 => 'at', 2 => qr/^(noon)$/i },
         [],
         [],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 2 => [ $flag{noon_midnight} ] },
           ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_daytime' ],
         {},
       ],
       [
         { 0 => qr/^(today)$/i, 1 => 'at', 2 => qr/^(midnight)$/i },
         [],
         [],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 2 => [ $flag{noon_midnight} ] },
           ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_daytime' ],
         {},
       ],
       [
         { 0 => qr/^(tomorrow)$/i, 1 => 'at', 2 => qr/^(noon)$/i },
         [],
         [],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 2 => [ $flag{noon_midnight} ] },
           ]
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_daytime' ],
         {},
       ],
       [
         { 0 => qr/^(tomorrow)$/i, 1 => 'at', 2 => qr/^(midnight)$/i },
         [],
         [],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 2 => [ $flag{noon_midnight} ] },
           ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_daytime' ],
         {},
       ],
    ],
    daytime_variant_weekday => [
       [ 'REGEXP', 'REGEXP', 'REGEXP' ],
       [
         { 0 => qr/^(noon)$/i, 1 => qr/^(next)$/i, 2 => $RE{weekday} },
         [],
         [],
         [
           [
             { 0 => [ $flag{noon_midnight} ] },
           ],
           [
             { 1 => [ $flag{last_this_next} ] },
             { 2 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {}, {} ],
         [ '_daytime', '_count_day_variant_week' ],
         {},
       ],
       [
         { 0 => qr/^(midnight)$/i, 1 => qr/^(next)$/i, 2 => $RE{weekday} },
         [],
         [],
         [
           [
             { 0 => [ $flag{noon_midnight} ] },
           ],
           [
             { 1 => [ $flag{last_this_next} ] },
             { 2 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {}, {} ],
         [ '_daytime', '_count_day_variant_week' ],
         {},
       ],
       [
         { 0 => qr/^(noon)$/i, 1 => qr/^(this)$/i, 2 => $RE{weekday} },
         [],
         [],
         [
           [
             { 0 => [ $flag{noon_midnight} ] },
           ],
           [
             { 1 => [ $flag{last_this_next} ] },
             { 2 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {}, {} ],
         [ '_daytime', '_count_day_variant_week' ],
         {},
       ],
       [
         { 0 => qr/^(midnight)$/i, 1 => qr/^(this)$/i, 2 => $RE{weekday} },
         [],
         [],
         [
           [
             { 0 => [ $flag{noon_midnight} ] },
           ],
           [
             { 1 => [ $flag{last_this_next} ] },
             { 2 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {}, {} ],
         [ '_daytime', '_count_day_variant_week' ],
         {},
       ],
       [
         { 0 => qr/^(noon)$/i, 1 => qr/^(last)$/i, 2 => $RE{weekday} },
         [],
         [],
         [
           [
             { 0 => [ $flag{noon_midnight} ] },
           ],
           [
             { 1 => [ $flag{last_this_next} ] },
             { 2 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {}, {} ],
         [ '_daytime', '_count_day_variant_week' ],
         {},
       ],
       [
         { 0 => qr/^(midnight)$/i, 1 => qr/^(last)$/i, 2 => $RE{weekday} },
         [],
         [],
         [
           [
             { 0 => [ $flag{noon_midnight} ] },
           ],
           [
             { 1 => [ $flag{last_this_next} ] },
             { 2 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {}, {} ],
         [ '_daytime', '_count_day_variant_week' ],
         {},
       ],
    ],
    this_daytime => [
       [ 'SCALAR', 'REGEXP' ],
       [
         { 0 => 'this', 1 => qr/^(morning)$/i },
         [],
         [],
         [
           [
             { 1 => [ $flag{morn_aftern_even} ] },
           ],
         ],
         [ {} ],
         [ '_daytime_variant' ],
         {},
       ],
       [
         { 0 => 'this', 1 => qr/^(afternoon)$/i },
         [],
         [],
         [
           [
             { 1 => [ $flag{morn_aftern_even} ] },
           ]
         ],
         [ {} ],
         [ '_daytime_variant' ],
         {},
       ],
       [
         { 0 => 'this', 1 => qr/^(evening)$/i },
         [],
         [],
         [
           [
             { 1 => [ $flag{morn_aftern_even} ] },
           ],
         ],
         [ {} ],
         [ '_daytime_variant' ],
         {},
       ],
    ],
    dayframe_day => [
       [ 'REGEXP', 'REGEXP' ],
       [
         { 0 => qr/^(yesterday)$/i, 1 => qr/^(morning)$/i },
         [],
         [],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 1 => [ $flag{morn_aftern_even} ] },
           ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_daytime_variant' ],
         {},
       ],
       [
         { 0 => qr/^(yesterday)$/i, 1 => qr/^(afternoon)$/i },
         [],
         [],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 1 => [ $flag{morn_aftern_even} ] },
           ]
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_daytime_variant' ],
         {},
       ],
       [
         { 0 => qr/^(yesterday)$/i, 1 => qr/^(evening)$/i },
         [],
         [],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 1 => [ $flag{morn_aftern_even} ] },
           ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_daytime_variant' ],
         {},
       ],
       [
         { 0 => qr/^(today)$/i, 1 => qr/^(morning)$/i },
         [],
         [],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 1 => [ $flag{morn_aftern_even} ] },
           ]
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_daytime_variant' ],
         {},
       ],
       [
         { 0 => qr/^(today)$/i, 1 => qr/^(afternoon)$/i },
         [],
         [],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 1 => [ $flag{morn_aftern_even} ] },
           ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_daytime_variant' ],
         {},
       ],
       [
         { 0 => qr/^(today)$/i, 1 => qr/^(evening)$/i },
         [],
         [],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 1 => [ $flag{morn_aftern_even} ] },
           ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_daytime_variant' ],
         {},
       ],
       [
         { 0 => qr/^(tomorrow)$/i, 1 => qr/^(morning)$/i },
         [],
         [],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 1 => [ $flag{morn_aftern_even} ] },
           ]
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_daytime_variant' ],
         {},
       ],
       [
         { 0 => qr/^(tomorrow)$/i, 1 => qr/^(afternoon)$/i },
         [],
         [],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 1 => [ $flag{morn_aftern_even} ] },
           ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_daytime_variant' ],
         {},
       ],
       [
         { 0 => qr/^(tomorrow)$/i, 1 => qr/^(evening)$/i },
         [],
         [],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 1 => [ $flag{morn_aftern_even} ] },
           ]
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_daytime_variant' ],
         {},
       ]
    ],
    at_daytime => [
       [ 'REGEXP', 'REGEXP' ],
       [
         { 0 => $RE{time}, 1 => qr/^(yesterday)$/i },
         [],
         [],
         [
           [ 0 ],
           [
             { 1 => [ $flag{yes_today_tom} ] },
           ],
         ],
         [ {}, { unit => 'day' } ],
         [ '_time', '_unit_variant' ],
         { truncate_to => 'minute' },
       ],
       [
         { 0 => $RE{time}, 1 => qr/^(today)$/i },
         [],
         [],
         [
           [ 0 ],
           [
             { 1 => [ $flag{yes_today_tom} ] },
           ],
         ],
         [ {}, { unit => 'day' } ],
         [ '_time', '_unit_variant' ],
         { truncate_to => 'minute' },
       ],
       [
         { 0 => $RE{time}, 1 => qr/^(tomorrow)$/i },
         [],
         [],
         [
           [ 0 ],
           [
             { 1 => [ $flag{yes_today_tom} ] },
           ],
         ],
         [ {}, { unit => 'day' } ],
         [ '_time', '_unit_variant' ],
         { truncate_to => 'minute' },
       ],
       [
         { 0 => $RE{time_am}, 1 => qr/^(yesterday)$/i },
         [ [ 0 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{time_am} ] },
           ],
           [
             { 1 => [ $flag{yes_today_tom} ] },
           ],
         ],
         [ {}, { unit => 'day' } ],
         [ '_at', '_unit_variant' ],
         { truncate_to => 'minute' },
       ],
       [
         { 0 => $RE{time_am}, 1 => qr/^(today)$/i },
         [ [ 0 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{time_am} ] },
           ],
           [
             { 1 => [ $flag{yes_today_tom} ] },
           ],
         ],
         [ {}, { unit => 'day' } ],
         [ '_at', '_unit_variant' ],
         { truncate_to => 'minute' },
       ],
       [
         { 0 => $RE{time_am}, 1 => qr/^(tomorrow)$/i },
         [ [ 0 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{time_am} ] },
           ],
           [
             { 1 => [ $flag{yes_today_tom} ] },
           ],
         ],
         [ {}, { unit => 'day' } ],
         [ '_at', '_unit_variant' ],
         { truncate_to => 'minute' },
       ],
       [
         { 0 => $RE{time_pm}, 1 => qr/^(yesterday)$/i },
         [ [ 0 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{time_pm} ] },
           ],
           [
             { 1 => [ $flag{yes_today_tom} ] },
           ],
         ],
         [ {}, { unit => 'day' } ],
         [ '_at', '_unit_variant' ],
         { truncate_to => 'minute' },
       ],
       [
         { 0 => $RE{time_pm}, 1 => qr/^(today)$/i },
         [ [ 0 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{time_pm} ] },
           ],
           [
             { 1 => [ $flag{yes_today_tom} ] },
           ],
         ],
         [ {}, { unit => 'day' } ],
         [ '_at', '_unit_variant' ],
         { truncate_to => 'minute' },
       ],
       [
         { 0 => $RE{time_pm}, 1 => qr/^(tomorrow)$/i },
         [ [ 0 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{time_pm} ] },
           ],
           [
             { 1 => [ $flag{yes_today_tom} ] },
           ],
         ],
         [ {}, { unit => 'day' } ],
         [ '_at', '_unit_variant' ],
         { truncate_to => 'minute' },
       ],
    ],
    at_variant_weekday => [
       [ 'REGEXP', 'REGEXP', 'REGEXP' ],
       [
         { 0 => $RE{time}, 1 => qr/^(next)$/i, 2 => $RE{weekday} },
         [],
         [],
         [
           [ 0 ],
           [
             { 1 => [ $flag{last_this_next} ] },
             { 2 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {}, {} ],
         [ '_time', '_count_day_variant_week' ],
         { truncate_to => 'minute' },
       ],
       [
         { 0 => $RE{time}, 1 => qr/^(this)$/i, 2 => $RE{weekday} },
         [],
         [],
         [
           [ 0 ],
           [
             { 1 => [ $flag{last_this_next} ] },
             { 2 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {}, {} ],
         [ '_time', '_count_day_variant_week' ],
         { truncate_to => 'minute' },
       ],
       [
         { 0 => $RE{time}, 1 => qr/^(last)$/i, 2 => $RE{weekday} },
         [],
         [],
         [
           [ 0 ],
           [
             { 1 => [ $flag{last_this_next} ] },
             { 2 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {}, {} ],
         [ '_time', '_count_day_variant_week' ],
         { truncate_to => 'minute' },
       ],
       [
         { 0 => $RE{time_am}, 1 => qr/^(next)$/i, 2 => $RE{weekday} },
         [ [ 0 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{time_am} ] },
           ],
           [
             { 1 => [ $flag{last_this_next} ] },
             { 2 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {}, {} ],
         [ '_at', '_count_day_variant_week' ],
         { truncate_to => 'minute' },
       ],
       [
         { 0 => $RE{time_am}, 1 => qr/^(this)$/i, 2 => $RE{weekday} },
         [ [ 0 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{time_am} ] },
           ],
           [
             { 1 => [ $flag{last_this_next} ] },
             { 2 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {}, {} ],
         [ '_at', '_count_day_variant_week' ],
         { truncate_to => 'minute' },
       ],
       [
         { 0 => $RE{time_am}, 1 => qr/^(last)$/i, 2 => $RE{weekday} },
         [ [ 0 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{time_am} ] },
           ],
           [
             { 1 => [ $flag{last_this_next} ] },
             { 2 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {}, {} ],
         [ '_at', '_count_day_variant_week' ],
         { truncate_to => 'minute' },
       ],
       [
         { 0 => $RE{time_pm}, 1 => qr/^(next)$/i, 2 => $RE{weekday} },
         [ [ 0 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{time_pm} ] },
           ],
           [
             { 1 => [ $flag{last_this_next} ] },
             { 2 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {}, {} ],
         [ '_at', '_count_day_variant_week' ],
         { truncate_to => 'minute' },
       ],
       [
         { 0 => $RE{time_pm}, 1 => qr/^(this)$/i, 2 => $RE{weekday} },
         [ [ 0 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{time_pm} ] },
           ],
           [
             { 1 => [ $flag{last_this_next} ] },
             { 2 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {}, {} ],
         [ '_at', '_count_day_variant_week' ],
         { truncate_to => 'minute' },
       ],
       [
         { 0 => $RE{time_pm}, 1 => qr/^(last)$/i, 2 => $RE{weekday} },
         [ [ 0 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{time_pm} ] },
           ],
           [
             { 1 => [ $flag{last_this_next} ] },
             { 2 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {}, {} ],
         [ '_at', '_count_day_variant_week' ],
         { truncate_to => 'minute' },
       ],
    ],
    month => [
       [ 'REGEXP' ],
       [
         { 0 => $RE{month} },
         [],
         [],
         [
           [
             { 0 => [ $flag{month_name}, $flag{month_num} ] },
           ],
         ],
         [ { unit => 'month' } ],
         [ '_unit_date' ],
         {
           prefer_future => true,
           truncate_to   => 'month',
         },
       ],
    ],
    month_day => [
       [ 'REGEXP', 'REGEXP' ],
       [
         { 0 => $RE{monthday}, 1 => $RE{month} },
         [ [ 0 ] ],
         [ $extended_checks{ordinal} ],
         [
           [
               0,
             { 1 => [ $flag{month_name}, $flag{month_num} ] },
           ],
         ],
         [ {} ],
         [ '_month_day' ],
         {
           prefer_future => true,
           truncate_to   => 'day',
         },
       ],
       [
         { 0 => $RE{month}, 1 => $RE{monthday} },
         [ [ 1 ] ],
         [ $extended_checks{ordinal} ],
         [
           [
               1,
             { 0 => [ $flag{month_name}, $flag{month_num} ] },
           ],
         ],
         [ {} ],
         [ '_month_day' ],
         {
           prefer_future => true,
           truncate_to   => 'day',
         },
       ]
    ],
    month_day_at => [
       [ 'REGEXP', 'REGEXP', 'REGEXP' ],
       [
         { 0 => $RE{month}, 1 => $RE{monthday}, 2 => $RE{time} },
         [ [ 1 ] ],
         [ $extended_checks{ordinal} ],
         [
           [
               1,
             { 0 => [ $flag{month_name}, $flag{month_num} ] },
           ],
           [ 2 ],
         ],
         [ {}, {} ],
         [ '_month_day', '_time' ],
         { truncate_to => 'minute' },
       ],
       [
         { 0 => $RE{month}, 1 => $RE{monthday}, 2 => $RE{time_am} },
         [ [ 1 ], [ 2 ] ],
         [ $extended_checks{ordinal}, $extended_checks{meridiem} ],
         [
           [
               1,
             { 0 => [ $flag{month_name}, $flag{month_num} ] },
           ],
           [
             { 2 => [ $flag{time_am} ] },
           ],
         ],
         [ {}, {} ],
         [ '_month_day', '_at' ],
         { truncate_to => 'minute' },
       ],
       [
         { 0 => $RE{month}, 1 => $RE{monthday}, 2 => $RE{time_pm} },
         [ [ 1 ], [ 2 ] ],
         [ $extended_checks{ordinal}, $extended_checks{meridiem} ],
         [
           [
               1,
             { 0 => [ $flag{month_name}, $flag{month_num} ] },
           ],
           [
             { 2 => [ $flag{time_pm} ] },
           ],
         ],
         [ {}, {} ],
         [ '_month_day', '_at' ],
         { truncate_to => 'minute' },
       ],
    ],
    day_month_year_ago => [
      [ 'REGEXP', 'REGEXP', 'REGEXP', 'REGEXP', 'SCALAR' ],
      [
        { 0 => $RE{monthday}, 1 => $RE{month}, 2 => $RE{number}, 3 => qr/^(years?)$/i, 4 => 'ago' },
        [ [ 0 ], [ 2, 3 ] ],
        [ $extended_checks{ordinal}, $extended_checks{suffix} ],
        [
          [
              0,
            { 1 => [ $flag{month_name}, $flag{month_num} ] },
          ],
          [ 2 ],
        ],
        [ {}, { unit => 'year' } ],
        [ '_month_day', '_ago_variant' ],
        { truncate_to => 'day' },
      ],
    ],
    day_month_variant_year => [
      [ 'REGEXP', 'REGEXP', 'REGEXP', 'SCALAR' ],
      [
        { 0 => $RE{monthday}, 1 => $RE{month}, 2 => qr/^(next)$/i, 3 => 'year' },
        [ [ 0 ] ],
        [ $extended_checks{ordinal} ],
        [
          [
              0,
            { 1 => [ $flag{month_name}, $flag{month_num} ] },
          ],
          [
            { 2 => [ $flag{last_this_next} ] },
          ],
        ],
        [ {}, { unit => 'year' } ],
        [ '_month_day', '_unit_variant' ],
        { truncate_to => 'day' },
      ],
      [
        { 0 => $RE{monthday}, 1 => $RE{month}, 2 => qr/^(this)$/i, 3 => 'year' },
        [ [ 0 ] ],
        [ $extended_checks{ordinal} ],
        [
          [
              0,
            { 1 => [ $flag{month_name}, $flag{month_num} ] },
          ],
          [
            { 2 => [ $flag{last_this_next} ] },
          ],
        ],
        [ {}, { unit => 'year' } ],
        [ '_month_day', '_unit_variant' ],
        { truncate_to => 'day' },
      ],
      [
        { 0 => $RE{monthday}, 1 => $RE{month}, 2 => qr/^(last)$/i, 3 => 'year' },
        [ [ 0 ] ],
        [ $extended_checks{ordinal} ],
        [
          [
              0,
            { 1 => [ $flag{month_name}, $flag{month_num} ] },
          ],
          [
            { 2 => [ $flag{last_this_next} ] },
          ]
        ],
        [ {}, { unit => 'year' } ],
        [ '_month_day', '_unit_variant' ],
        { truncate_to => 'day' },
      ],
    ],
    month_day_year => [
       [ 'REGEXP', 'REGEXP', 'REGEXP' ],
       [
         { 0 => $RE{month}, 1 => $RE{monthday}, 2 => $RE{year} },
         [ [ 1 ] ],
         [ $extended_checks{ordinal} ],
         [
           [
               1,
             { 0 => [ $flag{month_name}, $flag{month_num} ] },
           ],
           [ 2 ],
         ],
         [ {}, { unit => 'year' } ],
         [ '_month_day', '_unit_date' ],
         { truncate_to => 'day' },
       ]
    ],
    week_variant => [
       [ 'REGEXP', 'SCALAR' ],
       [
         { 0 => qr/^(next)$/i, 1 => 'week' },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
           ],
         ],
         [ { unit => 'week' } ],
         [ '_unit_variant' ],
         { truncate_to => 'day' },
       ],
       [
         { 0 => qr/^(this)$/i, 1 => 'week' },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
           ],
         ],
         [ { unit => 'week' } ],
         [ '_unit_variant' ],
         { truncate_to => 'day' },
       ],
       [
         { 0 => qr/^(last)$/i, 1 => 'week' },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
           ]
         ],
         [ { unit => 'week' } ],
         [ '_unit_variant' ],
         { truncate_to => 'day' },
       ]
    ],
    weekday => [
       [ 'REGEXP' ],
       [
         { 0 => $RE{weekday} },
         [],
         [],
         [
           [
             { 0 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ]
         ],
         [ {} ],
         [ '_weekday' ],
         {
           prefer_future => true,
           truncate_to   => 'day',
         },
       ],
    ],
    weekday_variant => [
       [ 'REGEXP', 'REGEXP' ],
       [
         { 0 => qr/^(next)$/i, 1 => $RE{weekday} },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
             { 1 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {} ],
         [ '_count_day_variant_week' ],
         { truncate_to => 'day' },
       ],
       [
         { 0 => qr/^(this)$/i, 1 => $RE{weekday} },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
             { 1 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {} ],
         [ '_count_day_variant_week' ],
         { truncate_to => 'day' },
       ],
       [
         { 0 => qr/^(last)$/i, 1 => $RE{weekday} },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
             { 1 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {} ],
         [ '_count_day_variant_week' ],
         { truncate_to => 'day' },
       ],
    ],
    year_variant => [
       [ 'REGEXP', 'SCALAR' ],
       [
         { 0 => qr/^(last)$/i, 1 => 'year' },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
           ],
         ],
         [ { unit => 'year' } ],
         [ '_unit_variant' ],
         { truncate_to => 'year' },
       ],
       [
         { 0 => qr/^(this)$/i, 1 => 'year' },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
           ],
         ],
         [ { unit => 'year' } ],
         [ '_unit_variant' ],
         { truncate_to => 'year' },
       ],
       [
         { 0 => qr/^(next)$/i, 1 => 'year' },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
           ],
         ],
         [ { unit => 'year' } ],
         [ '_unit_variant' ],
         { truncate_to => 'year' }
       ],
    ],
    month_variant => [
       [ 'REGEXP', 'REGEXP' ],
       [
         { 0 => qr/^(last)$/i, 1 => $RE{month} },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
             { 1 => [ $flag{month_name}, $flag{month_num} ] },
           ],
         ],
         [ {} ],
         [ '_month_variant' ],
         { truncate_to => 'month' },
       ],
       [
         { 0 => qr/^(this)$/i, 1 => $RE{month} },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
             { 1 => [ $flag{month_name}, $flag{month_num} ] },
           ]
         ],
         [ {} ],
         [ '_month_variant' ],
         { truncate_to => 'month' },
       ],
       [
         { 0 => qr/^(next)$/i, 1 => $RE{month} },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
             { 1 => [ $flag{month_name}, $flag{month_num} ] },
           ],
         ],
         [ {} ],
         [ '_month_variant' ],
         { truncate_to => 'month' },
       ],
    ],
    unit_literal_variant => [
       [ 'REGEXP', 'SCALAR' ],
       [
         { 0 => qr/^(last)$/i, 1 => 'second' },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
           ],
         ],
         [ { unit => 'second' } ],
         [ '_unit_variant' ],
         {},
       ],
       [
         { 0 => qr/^(this)$/i, 1 => 'second' },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
           ],
         ],
         [ { unit => 'second' } ],
         [ '_unit_variant' ],
         {},
       ],
       [
         { 0 => qr/^(next)$/i, 1 => 'second' },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
           ],
         ],
         [ { unit => 'second' } ],
         [ '_unit_variant' ],
         {},
       ],
       [
         { 0 => qr/^(last)$/i, 1 => 'minute' },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
           ],
         ],
         [ { unit => 'minute' } ],
         [ '_unit_variant' ],
         { truncate_to => 'minute' },
       ],
       [
         { 0 => qr/^(this)$/i, 1 => 'minute' },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
           ],
         ],
         [ { unit => 'minute' } ],
         [ '_unit_variant' ],
         { truncate_to => 'minute' },
       ],
       [
         { 0 => qr/^(next)$/i, 1 => 'minute' },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
           ],
         ],
         [ { unit => 'minute' } ],
         [ '_unit_variant' ],
         { truncate_to => 'minute' },
       ],
       [
         { 0 => qr/^(last)$/i, 1 => 'hour' },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
           ],
         ],
         [ { unit => 'hour' } ],
         [ '_unit_variant' ],
         { truncate_to => 'hour' },
       ],
       [
         { 0 => qr/^(this)$/i, 1 => 'hour' },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
           ],
         ],
         [ { unit => 'hour' } ],
         [ '_unit_variant' ],
         { truncate_to => 'hour' },
       ],
       [
         { 0 => qr/^(next)$/i, 1 => 'hour' },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
           ],
         ],
         [ { unit => 'hour' } ],
         [ '_unit_variant' ],
         { truncate_to => 'hour' },
       ],
       [
         { 0 => qr/^(last)$/i, 1 => 'day' },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
           ],
         ],
         [ { unit => 'day' } ],
         [ '_unit_variant' ],
         { truncate_to => 'day' },
       ],
       [
         { 0 => qr/^(this)$/i, 1 => 'day' },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
           ],
         ],
         [ { unit => 'day' } ],
         [ '_unit_variant' ],
         { truncate_to => 'day' },
       ],
       [
         { 0 => qr/^(next)$/i, 1 => 'day' },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
           ],
         ],
         [ { unit => 'day' } ],
         [ '_unit_variant' ],
         { truncate_to => 'day' },
       ],
       [
         { 0 => qr/^(last)$/i, 1 => 'month' },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
           ],
         ],
         [ { unit => 'month' } ],
         [ '_unit_variant' ],
         { truncate_to => 'month' },
       ],
       [
         { 0 => qr/^(this)$/i, 1 => 'month' },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
           ],
         ],
         [ { unit => 'month' } ],
         [ '_unit_variant' ],
         { truncate_to => 'month' },
       ],
       [
         { 0 => qr/^(next)$/i, 1 => 'month' },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
           ],
         ],
         [ { unit => 'month' } ],
         [ '_unit_variant' ],
         { truncate_to => 'month' },
       ],
    ],
    at => [
       [ 'REGEXP', 'SCALAR' ],
       [
         { 0 => $RE{time}, 1 => 'am' },
         [ [ 0 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{time_am} ] },
           ],
         ],
         [ {} ],
         [ '_at' ],
         {
           prefer_future => true,
           truncate_to   => 'minute',
         },
       ],
       [
         { 0 => $RE{time}, 1 => 'pm' },
         [ [ 0 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{time_pm} ] },
           ],
         ],
         [ {} ],
         [ '_at' ],
         {
           prefer_future => true,
           truncate_to   => 'minute',
         },
       ],
       [
         { 0 => $RE{time_full}, 1 => 'am' },
         [ [ 0 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{time_am} ] },
           ],
         ],
         [ {} ],
         [ '_time_full' ],
         { prefer_future => true },
       ],
       [
         { 0 => $RE{time_full}, 1 => 'pm' },
         [ [ 0 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{time_pm} ] },
           ],
         ],
         [ {} ],
         [ '_time_full' ],
         { prefer_future => true },
       ],
    ],
    at_combined => [
       [ 'REGEXP' ],
       [
         { 0 => $RE{time_am} },
         [ [ 0 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{time_am} ] },
           ],
         ],
         [ {} ],
         [ '_at' ],
         {
           prefer_future => true,
           truncate_to   => 'minute',
         },
       ],
       [
         { 0 => $RE{time_pm} },
         [ [ 0 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{time_pm} ] },
           ],
         ],
         [ {} ],
         [ '_at' ],
         {
           prefer_future => true,
           truncate_to   => 'minute',
         },
       ],
    ],
    weekday_time => [
       [ 'REGEXP', 'REGEXP' ],
       [
         { 0 => $RE{weekday}, 1 => $RE{time} },
         [],
         [],
         [
           [
             { 0 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
           [ 1 ],
         ],
         [ {}, {} ],
         [ '_weekday', '_time' ],
         {
           prefer_future => true,
           truncate_to   => 'minute',
         },
       ],
       [
         { 0 => $RE{weekday}, 1 => $RE{time_am} },
         [ [ 1 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
           [
             { 1 => [ $flag{time_am} ] },
           ],
         ],
         [ {}, {} ],
         [ '_weekday', '_at' ],
         {
           prefer_future => true,
           truncate_to   => 'minute',
         },
       ],
       [
         { 0 => $RE{weekday}, 1 => $RE{time_pm} },
         [ [ 1 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
           [
             { 1 => [ $flag{time_pm} ] },
           ],
         ],
         [ {}, {} ],
         [ '_weekday', '_at' ],
         {
           prefer_future => true,
           truncate_to   => 'minute',
         },
       ],
       [
         { 0 => $RE{time}, 1 => $RE{weekday} },
         [],
         [],
         [
           [ 0 ],
           [
             { 1 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {}, {} ],
         [ '_time', '_weekday' ],
         {
           prefer_future => true,
           truncate_to   => 'minute',
         },
       ],
       [
         { 0 => $RE{time_am}, 1 => $RE{weekday} },
         [ [ 0 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{time_am} ] },
           ],
           [
             { 1 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {}, {} ],
         [ '_at', '_weekday' ],
         {
           prefer_future => true,
           truncate_to   => 'minute',
         },
       ],
       [
         { 0 => $RE{time_pm}, 1 => $RE{weekday} },
         [ [ 0 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{time_pm} ] },
           ],
           [
             { 1 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {}, {} ],
         [ '_at', '_weekday' ],
         {
           prefer_future => true,
           truncate_to   => 'minute',
         },
       ],
    ],
    time => [
       [ 'REGEXP' ],
       [
         { 0 => $RE{time} },
         [],
         [],
         [ [ 0 ] ],
         [ {} ],
         [ '_time' ],
         {
           prefer_future => true,
           truncate_to   => 'minute',
         },
       ],
    ],
    time_full => [
       [ 'REGEXP' ],
       [
         { 0 => $RE{time_full} },
         [],
         [],
         [ [ 0 ] ],
         [ {} ],
         [ '_time_full' ],
         { prefer_future => true },
       ],
    ],
    month_year => [
       [ 'REGEXP', 'REGEXP' ],
       [
         { 0 => $RE{month}, 1 => $RE{year} },
         [],
         [],
         [
           [
             { 0 => [ $flag{month_name}, $flag{month_num} ] },
           ],
           [ 1 ],
         ],
         [ { unit => 'month' }, { unit => 'year' } ],
         [ '_unit_date', '_unit_date' ],
         { truncate_to => 'month' },
       ],
    ],
    year => [
       [ 'REGEXP' ],
       [
         { 0 => $RE{year} },
         [],
         [],
         [ [ 0 ] ],
         [ { unit => 'year' } ],
         [ '_unit_date' ],
         { truncate_to => 'year' },
       ],
    ],
    count_weekday => [
       [ 'REGEXP', 'REGEXP' ],
       [
         { 0 => $RE{day}, 1 => $RE{weekday} },
         [ [ 0 ] ],
         [ $extended_checks{ordinal} ],
         [
           [
               0,
             { 1 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {} ],
         [ '_count_weekday' ],
         { truncate_to => 'day' },
       ],
    ],
    count_yearday => [
       [ 'REGEXP', 'SCALAR' ],
       [
         { 0 => $RE{day}, 1 => 'day' },
         [ [ 0 ] ],
         [ $extended_checks{ordinal} ],
         [
           [
             0,
             { VALUE => 0 }
           ],
         ],
         [ {} ],
         [ '_count_yearday_variant_year' ],
         { truncate_to => 'day' },
       ],
    ],
    count_yearday_variant_year => [
        [ 'REGEXP', 'SCALAR', 'REGEXP', 'SCALAR' ],
        [
          { 0 => $RE{day}, 1 => 'day', 2 => qr/^(next)$/i, 3 => 'year' },
          [ [ 0 ] ],
          [ $extended_checks{ordinal} ],
          [
            [
                0,
              { 2 => [ $flag{last_this_next} ] },
            ],
          ],
          [ {} ],
          [ '_count_yearday_variant_year' ],
          { truncate_to => 'day' },
        ],
        [
          { 0 => $RE{day}, 1 => 'day', 2 => qr/^(this)$/i, 3 => 'year' },
          [ [ 0 ] ],
          [ $extended_checks{ordinal} ],
          [
            [
                0,
              { 2 => [ $flag{last_this_next} ] },
            ],
          ],
          [ {} ],
          [ '_count_yearday_variant_year' ],
          { truncate_to => 'day' },
        ],
        [
          { 0 => $RE{day}, 1 => 'day', 2 => qr/^(last)$/i, 3 => 'year' },
          [ [ 0 ] ],
          [ $extended_checks{ordinal} ],
          [
            [
                0,
              { 2 => [ $flag{last_this_next} ] },
            ],
          ],
          [ {} ],
          [ '_count_yearday_variant_year' ],
          { truncate_to => 'day' },
        ],
    ],
    daytime_in_the_variant => [
       [ 'REGEXP', 'SCALAR', 'SCALAR', 'SCALAR' ],
       [
         { 0 => $RE{number}, 1 => 'in', 2 => 'the', 3 => 'morning' },
         [],
         [],
         [ [ 0 ] ],
         [ {} ],
         [ '_daytime_in_the_variant' ],
         {},
       ],
       [
         { 0 => $RE{number}, 1 => 'in', 2 => 'the', 3 => 'afternoon' },
         [],
         [],
         [ [ 0 ] ],
         [ { hours => 12 } ],
         [ '_daytime_in_the_variant' ],
         {},
       ],
       [
         { 0 => $RE{number}, 1 => 'in', 2 => 'the', 3 => 'evening' },
         [],
         [],
         [ [ 0 ] ],
         [ { hours => 12 } ],
         [ '_daytime_in_the_variant' ],
         {},
       ],
    ],
    ago => [
       [ 'REGEXP', 'REGEXP', 'SCALAR' ],
       [
         { 0 => $RE{number}, 1 => qr/^(seconds?)$/i, 2 => 'ago' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [ [ 0 ] ],
         [ { unit => 'second' } ],
         [ '_ago_variant' ],
         {},
       ],
       [
         { 0 => $RE{number}, 1 => qr/^(minutes?)$/i, 2 => 'ago' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [ [ 0 ] ],
         [ { unit => 'minute' } ],
         [ '_ago_variant' ],
         {},
       ],
       [
         { 0 => $RE{number}, 1 => qr/^(hours?)$/i, 2 => 'ago' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [ [ 0 ] ],
         [ { unit => 'hour' } ],
         [ '_ago_variant' ],
         {},
       ],
       [
         { 0 => $RE{number}, 1 => qr/^(days?)$/i, 2 => 'ago' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [ [ 0 ] ],
         [ { unit => 'day' } ],
         [ '_ago_variant' ],
         {},
       ],
       [
         { 0 => $RE{number}, 1 => qr/^(weeks?)$/i, 2 => 'ago' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [ [ 0 ] ],
         [ { unit => 'week' } ],
         [ '_ago_variant' ],
         {},
       ],
       [
         { 0 => $RE{number}, 1 => qr/^(months?)$/i, 2 => 'ago' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [ [ 0 ] ],
         [ { unit => 'month' } ],
         [ '_ago_variant' ],
         {},
       ],
       [
         { 0 => $RE{number}, 1 => qr/^(years?)$/i, 2 => 'ago' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [ [ 0 ] ],
         [ { unit => 'year' } ],
         [ '_ago_variant' ],
         {},
       ],
    ],
    ago_tomorrow => [
       [ 'REGEXP', 'REGEXP', 'REGEXP', 'SCALAR' ],
       [
         { 0 => qr/^(tomorrow)$/i, 1 => $RE{number}, 2 => qr/^(seconds?)$/i, 3 => 'ago' },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [ 1 ],
         ],
         [ { unit => 'day' }, { unit => 'second' } ],
         [ '_unit_variant', '_ago_variant' ],
         {},
       ],
       [
         { 0 => qr/^(tomorrow)$/i, 1 => $RE{number}, 2 => qr/^(minutes?)$/i, 3 => 'ago' },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [ 1 ],
         ],
         [ { unit => 'day' }, { unit => 'minute' } ],
         [ '_unit_variant', '_ago_variant' ],
         {},
       ],
       [
         { 0 => qr/^(tomorrow)$/i, 1 => $RE{number}, 2 => qr/^(hours?)$/i, 3 => 'ago' },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [ 1 ],
         ],
         [ { unit => 'day' }, { unit => 'hour' } ],
         [ '_unit_variant', '_ago_variant' ],
         {},
       ],
       [
         { 0 => qr/^(tomorrow)$/i, 1 => $RE{number}, 2 => qr/^(days?)$/i, 3 => 'ago' },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [ 1 ],
         ],
         [ { unit => 'day' }, { unit => 'day' } ],
         [ '_unit_variant', '_ago_variant' ],
         {},
       ],
       [
         { 0 => qr/^(tomorrow)$/i, 1 => $RE{number}, 2 => qr/^(weeks?)$/i, 3 => 'ago' },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [ 1 ],
         ],
         [ { unit => 'day' }, { unit => 'week' } ],
         [ '_unit_variant', '_ago_variant' ],
         {},
       ],
       [
         { 0 => qr/^(tomorrow)$/i, 1 => $RE{number}, 2 => qr/^(months?)$/i, 3 => 'ago' },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [ 1 ],
         ],
         [ { unit => 'day' }, { unit => 'month' } ],
         [ '_unit_variant', '_ago_variant' ],
         {},
       ],
       [
         { 0 => qr/^(tomorrow)$/i, 1 => $RE{number}, 2 => qr/^(years?)$/i, 3 => 'ago' },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [ 1 ],
         ],
         [ { unit => 'day' }, { unit => 'year' } ],
         [ '_unit_variant', '_ago_variant' ],
         {},
       ],
    ],
    ago_yesterday => [
       [ 'REGEXP', 'REGEXP', 'REGEXP', 'SCALAR' ],
       [
         { 0 => qr/^(yesterday)$/i, 1 => $RE{number}, 2 => qr/^(seconds?)$/i, 3 => 'ago' },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [ 1 ],
         ],
         [ { unit => 'day' }, { unit => 'second' } ],
         [ '_unit_variant', '_ago_variant' ],
         {},
       ],
       [
         { 0 => qr/^(yesterday)$/i, 1 => $RE{number}, 2 => qr/^(minutes?)$/i, 3 => 'ago' },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [ 1 ],
         ],
         [ { unit => 'day' }, { unit => 'minute' } ],
         [ '_unit_variant', '_ago_variant' ],
         {},
       ],
       [
         { 0 => qr/^(yesterday)$/i, 1 => $RE{number}, 2 => qr/^(hours?)$/i, 3 => 'ago' },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [ 1 ],
         ],
         [ { unit => 'day' }, { unit => 'hour' } ],
         [ '_unit_variant', '_ago_variant' ],
         {},
       ],
       [
         { 0 => qr/^(yesterday)$/i, 1 => $RE{number}, 2 => qr/^(days?)$/i, 3 => 'ago' },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [ 1 ],
         ],
         [ { unit => 'day' }, { unit => 'day' } ],
         [ '_unit_variant', '_ago_variant' ],
         {},
       ],
       [
         { 0 => qr/^(yesterday)$/i, 1 => $RE{number}, 2 => qr/^(weeks?)$/i, 3 => 'ago' },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [ 1 ],
         ],
         [ { unit => 'day' }, { unit => 'week' } ],
         [ '_unit_variant', '_ago_variant' ],
         {},
       ],
       [
         { 0 => qr/^(yesterday)$/i, 1 => $RE{number}, 2 => qr/^(months?)$/i, 3 => 'ago' },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [ 1 ],
         ],
         [ { unit => 'day' }, { unit => 'month' } ],
         [ '_unit_variant', '_ago_variant' ],
         {},
       ],
       [
         { 0 => qr/^(yesterday)$/i, 1 => $RE{number}, 2 => qr/^(years?)$/i, 3 => 'ago' },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [ 1 ],
         ],
         [ { unit => 'day' }, { unit => 'year' } ],
         [ '_unit_variant', '_ago_variant' ],
         {},
       ],
    ],
    weekday_ago_at_time => [
       [ 'REGEXP', 'REGEXP', 'REGEXP', 'SCALAR', 'SCALAR', 'REGEXP' ],
       [
         { 0 => $RE{weekday}, 1 => $RE{number}, 2 => qr/^(months?)$/i, 3 => 'ago', 4 => 'at', 5 => $RE{time} },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [ 1 ],
           [
             { 0 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
           [ 5 ],
         ],
         [ { unit => 'month' }, {}, {} ],
         [ '_ago_variant', '_weekday', '_time' ],
         { truncate_to => 'minute' },
       ],
       [
         { 0 => $RE{weekday}, 1 => $RE{number}, 2 => qr/^(months?)$/i, 3 => 'ago', 4 => 'at', 5 => $RE{time_am} },
         [ [ 1, 2 ], [ 5 ] ],
         [ $extended_checks{suffix}, $extended_checks{meridiem} ],
         [
           [ 1 ],
           [
             { 0 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
           [
             { 5 => [ $flag{time_am} ] },
           ],
         ],
         [ { unit => 'month' }, {}, {} ],
         [ '_ago_variant', '_weekday', '_at' ],
         { truncate_to => 'minute' },
       ],
       [
         { 0 => $RE{weekday}, 1 => $RE{number}, 2 => qr/^(months?)$/i, 3 => 'ago', 4 => 'at', 5 => $RE{time_pm} },
         [ [ 1, 2 ], [ 5 ] ],
         [ $extended_checks{suffix}, $extended_checks{meridiem} ],
         [
           [ 1 ],
           [
             { 0 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
           [
             { 5 => [ $flag{time_pm} ] },
           ],
         ],
         [ { unit => 'month' }, {}, {} ],
         [ '_ago_variant', '_weekday', '_at' ],
         { truncate_to => 'minute' },
       ],
    ],
    now_variant_before => [
       [ 'REGEXP', 'REGEXP', 'REGEXP', 'SCALAR' ],
       [
         { 0 => $RE{number}, 1 => qr/^(seconds?)$/i, 2 => qr/^(before)$/i, 3 => 'now' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [
           [
               0,
             { 2 => [ $flag{before_after_from} ] },
           ],
         ],
         [ { unit => 'second' } ],
         [ '_now_variant' ],
         {},
       ],
       [
         { 0 => $RE{number}, 1 => qr/^(minutes?)$/i, 2 => qr/^(before)$/i, 3 => 'now' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [
           [
               0,
             { 2 => [ $flag{before_after_from} ] },
           ],
         ],
         [ { unit => 'minute' } ],
         [ '_now_variant' ],
         {},
       ],
       [
         { 0 => $RE{number}, 1 => qr/^(hours?)$/i, 2 => qr/^(before)$/i, 3 => 'now' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [
           [
               0,
             { 2 => [ $flag{before_after_from} ] },
           ],
         ],
         [ { unit => 'hour' } ],
         [ '_now_variant' ],
         {},
       ],
       [
         { 0 => $RE{number}, 1 => qr/^(days?)$/i,  2 => qr/^(before)$/i, 3 => 'now' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [
           [
               0,
             { 2 => [ $flag{before_after_from} ] },
           ],
         ],
         [ { unit => 'day' } ],
         [ '_now_variant' ],
         {},
       ],
       [
         { 0 => $RE{number}, 1 => qr/^(weeks?)$/i, 2 => qr/^(before)$/i, 3 => 'now' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [
           [
               0,
             { 2 => [ $flag{before_after_from} ] },
           ],
         ],
         [ { unit => 'week' } ],
         [ '_now_variant' ],
         {},
       ],
       [
         { 0 => $RE{number}, 1 => qr/^(months?)$/i, 2 => qr/^(before)$/i, 3 => 'now' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [
           [
               0,
             { 2 => [ $flag{before_after_from} ] },
           ]
         ],
         [ { unit => 'month' } ],
         [ '_now_variant' ],
         {},
       ],
       [
         { 0 => $RE{number}, 1 => qr/^(years?)$/i, 2 => qr/^(before)$/i, 3 => 'now' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [
           [
               0,
             { 2 => [ $flag{before_after_from} ] },
           ],
         ],
         [ { unit => 'year' } ],
         [ '_now_variant' ],
         {},
       ],
    ],
    now_variant_from => [
       [ 'REGEXP', 'REGEXP', 'REGEXP', 'SCALAR' ],
       [
         { 0 => $RE{number}, 1 => qr/^(seconds?)$/i, 2 => qr/^(from)$/i, 3 => 'now' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [
           [
               0,
             { 2 => [ $flag{before_after_from} ] },
           ],
         ],
         [ { unit => 'second' } ],
         [ '_now_variant' ],
         {},
       ],
       [
         { 0 => $RE{number}, 1 => qr/^(minutes?)$/i, 2 => qr/^(from)$/i, 3 => 'now' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [
           [
               0,
             { 2 => [ $flag{before_after_from} ] },
           ],
         ],
         [ { unit => 'minute' } ],
         [ '_now_variant' ],
         {},
       ],
       [
         { 0 => $RE{number}, 1 => qr/^(hours?)$/i, 2 => qr/^(from)$/i, 3 => 'now' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [
           [
               0,
             { 2 => [ $flag{before_after_from} ] },
           ],
         ],
         [ { unit => 'hour' } ],
         [ '_now_variant' ],
         {},
       ],
       [
         { 0 => $RE{number}, 1 => qr/^(days?)$/i, 2 => qr/^(from)$/i, 3 => 'now' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [
           [
               0,
             { 2 => [ $flag{before_after_from} ] },
           ],
         ],
         [ { unit => 'day' } ],
         [ '_now_variant' ],
         {},
       ],
       [
         { 0 => $RE{number}, 1 => qr/^(weeks?)$/i, 2 => qr/^(from)$/i, 3 => 'now' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [
           [
               0,
             { 2 => [ $flag{before_after_from} ] },
           ],
         ],
         [ { unit => 'week' } ],
         [ '_now_variant' ],
         {},
       ],
       [
         { 0 => $RE{number}, 1 => qr/^(months?)$/i, 2 => qr/^(from)$/i, 3 => 'now' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [
           [
               0,
             { 2 => [ $flag{before_after_from} ] },
           ],
         ],
         [ { unit => 'month' } ],
         [ '_now_variant' ],
         {},
       ],
       [
         { 0 => $RE{number}, 1 => qr/^(years?)$/i, 2 => qr/^(from)$/i, 3 => 'now' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [
           [
               0,
             { 2 => [ $flag{before_after_from} ] },
           ],
         ],
         [ { unit => 'year' } ],
         [ '_now_variant' ],
         {},
       ],
    ],
    day_daytime => [
       [ 'REGEXP', 'REGEXP', 'SCALAR', 'SCALAR', 'SCALAR' ],
       [
         { 0 => $RE{weekday}, 1 => $RE{number}, 2 => 'in', 3 => 'the', 4 => 'morning' },
         [],
         [],
         [
           [
             { 0 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
           [ 1 ],
         ],
         [ {}, {} ],
         [ '_weekday', '_daytime_in_the_variant' ],
         {},
       ],
       [
         { 0 => $RE{weekday}, 1 => $RE{number}, 2 => 'in', 3 => 'the', 4 => 'afternoon' },
         [],
         [],
         [
           [
             { 0 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
           [ 1 ],
         ],
         [ {}, { hours => 12 } ],
         [ '_weekday', '_daytime_in_the_variant' ],
         {},
       ],
       [
         { 0 => $RE{weekday}, 1 => $RE{number}, 2 => 'in', 3 => 'the', 4 => 'evening' },
         [],
         [],
         [
           [
             { 0 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
           [ 1 ],
         ],
         [ {}, { hours => 12 } ],
         [ '_weekday', '_daytime_in_the_variant' ],
         {},
       ],
    ],
    variant_weekday_at_time => [
       [ 'REGEXP', 'REGEXP', 'SCALAR', 'REGEXP' ],
       [
         { 0 => qr/^(next)$/i, 1 => $RE{weekday}, 2 => 'at', 3 => $RE{time} },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
             { 1 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
           [ 3 ],
         ],
         [ {}, {} ],
         [ '_count_day_variant_week', '_time' ],
         { truncate_to => 'minute' },
       ],
       [
         { 0 => qr/^(this)$/i, 1 => $RE{weekday}, 2 => 'at', 3 => $RE{time} },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
             { 1 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
           [ 3 ],
         ],
         [ {}, {} ],
         [ '_count_day_variant_week', '_time' ],
         { truncate_to => 'minute' },
       ],
       [
         { 0 => qr/^(last)$/i, 1 => $RE{weekday}, 2 => 'at', 3 => $RE{time} },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
             { 1 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
           [ 3 ],
         ],
         [ {}, {} ],
         [ '_count_day_variant_week', '_time' ],
         { truncate_to => 'minute' },
       ],
    ],
    count_day_variant_week => [
       [ 'REGEXP', 'SCALAR', 'REGEXP', 'SCALAR' ],
       [
         { 0 => $RE{day}, 1 => 'day', 2 => qr/^(next)$/i, 3 => 'week' },
         [ [ 0 ] ],
         [ $extended_checks{ordinal} ],
         [
           [
             { 2 => [ $flag{last_this_next} ] },
               0,
           ],
         ],
         [ {} ],
         [ '_count_day_variant_week' ],
         { truncate_to => 'day' },
       ],
       [
         { 0 => $RE{day}, 1 => 'day', 2 => qr/^(this)$/i, 3 => 'week' },
         [ [ 0 ] ],
         [ $extended_checks{ordinal} ],
         [
           [
             { 2 => [ $flag{last_this_next} ] },
               0,
           ],
         ],
         [ {} ],
         [ '_count_day_variant_week' ],
         { truncate_to => 'day' },
       ],
       [
         { 0 => $RE{day}, 1 => 'day', 2 => qr/^(last)$/i, 3 => 'week' },
         [ [ 0 ] ],
         [ $extended_checks{ordinal} ],
         [
           [
             { 2 => [ $flag{last_this_next} ] },
               0,
           ],
         ],
         [ {} ],
         [ '_count_day_variant_week' ],
         { truncate_to => 'day' },
       ],
    ],
    count_day_variant_month => [
       [ 'REGEXP', 'SCALAR', 'REGEXP', 'SCALAR' ],
       [
         { 0 => $RE{day}, 1 => 'day', 2 => qr/^(next)$/i, 3 => 'month' },
         [ [ 0 ] ],
         [ $extended_checks{ordinal} ],
         [
           [
             { 2 => [ $flag{last_this_next} ] },
               0,
           ],
         ],
         [ {} ],
         [ '_count_day_variant_month' ],
         { truncate_to => 'day' },
       ],
       [
         { 0 => $RE{day}, 1 => 'day', 2 => qr/^(this)$/i, 3 => 'month' },
         [ [ 0 ] ],
         [ $extended_checks{ordinal} ],
         [
           [
             { 2 => [ $flag{last_this_next} ] },
               0,
           ],
         ],
         [ {} ],
         [ '_count_day_variant_month' ],
         { truncate_to => 'day' },
       ],
       [
         { 0 => $RE{day}, 1 => 'day', 2 => qr/^(last)$/i, 3 => 'month' },
         [ [ 0 ] ],
         [ $extended_checks{ordinal} ],
         [
           [
             { 2 => [ $flag{last_this_next} ] },
               0,
           ],
         ],
         [ {} ],
         [ '_count_day_variant_month' ],
         { truncate_to => 'day' },
       ],
    ],
    weekday_variant_week => [
       [ 'REGEXP', 'REGEXP', 'SCALAR' ],
       [
         { 0 => $RE{weekday}, 1 => qr/^(next)$/i, 2 => 'week' },
         [],
         [],
         [
           [
             { 1 => [ $flag{last_this_next} ] },
             { 0 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {} ],
         [ '_count_day_variant_week' ],
         { truncate_to => 'day' },
       ],
       [
         { 0 => $RE{weekday}, 1 => qr/^(this)$/i, 2 => 'week' },
         [],
         [],
         [
           [
             { 1 => [ $flag{last_this_next} ] },
             { 0 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {} ],
         [ '_count_day_variant_week' ],
         { truncate_to => 'day' },
       ],
       [
         { 0 => $RE{weekday}, 1 => qr/^(last)$/i, 2 => 'week' },
         [],
         [],
         [
           [
             { 1 => [ $flag{last_this_next} ] },
             { 0 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ]
         ],
         [ {} ],
         [ '_count_day_variant_week' ],
         { truncate_to => 'day' },
       ],
    ],
    variant_week_weekday => [
       [ 'REGEXP', 'SCALAR', 'REGEXP' ],
       [
         { 0 => qr/^(next)$/i, 1 => 'week', 2 => $RE{weekday} },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
             { 2 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {} ],
         [ '_count_day_variant_week' ],
         { truncate_to => 'day' },
       ],
       [
         { 0 => qr/^(this)$/i, 1 => 'week', 2 => $RE{weekday} },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
             { 2 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {} ],
         [ '_count_day_variant_week' ],
         { truncate_to => 'day' },
       ],
       [
         { 0 => qr/^(last)$/i, 1 => 'week', 2 => $RE{weekday} },
         [],
         [],
         [
           [
             { 0 => [ $flag{last_this_next} ] },
             { 2 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {} ],
         [ '_count_day_variant_week' ],
         { truncate_to => 'day' },
       ],
    ],
    count_month_variant_year => [
       [ 'REGEXP', 'SCALAR', 'REGEXP', 'SCALAR' ],
       [
         { 0 => $RE{day}, 1 => 'month', 2 => qr/^(next)$/i, 3 => 'year' },
         [ [ 0 ] ],
         [ $extended_checks{ordinal} ],
         [
           [
             { 2 => [ $flag{last_this_next} ] },
               0,
           ],
         ],
         [ {} ],
         [ '_count_month_variant_year' ],
         { truncate_to => 'month' },
       ],
       [
         { 0 => $RE{day}, 1 => 'month', 2 => qr/^(this)$/i, 3 => 'year' },
         [ [ 0 ] ],
         [ $extended_checks{ordinal} ],
         [
           [
             { 2 => [ $flag{last_this_next} ] },
               0,
           ],
         ],
         [ {} ],
         [ '_count_month_variant_year' ],
         { truncate_to => 'month' },
       ],
       [
         { 0 => $RE{day}, 1 => 'month', 2 => qr/^(last)$/i, 3 => 'year' },
         [ [ 0 ] ],
         [ $extended_checks{ordinal} ],
         [
           [
             { 2 => [ $flag{last_this_next} ] },
               0,
           ],
         ],
         [ {} ],
         [ '_count_month_variant_year' ],
         { truncate_to => 'month' },
       ],
    ],
    in_count_unit => [
       [ 'SCALAR', 'REGEXP', 'REGEXP' ],
       [
         { 0 => 'in', 1 => $RE{number}, 2 => qr/^(seconds?)$/i },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [ [ 1 ] ],
         [ { unit => 'second' } ],
         [ '_in_count_variant' ],
         {},
       ],
       [
         { 0 => 'in', 1 => $RE{number}, 2 => qr/^(minutes?)$/i },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [ [ 1 ] ],
         [ { unit => 'minute' } ],
         [ '_in_count_variant' ],
         {},
       ],
       [
         { 0 => 'in', 1 => $RE{number}, 2 => qr/^(hours?)$/i },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [ [ 1 ] ],
         [ { unit => 'hour' } ],
         [ '_in_count_variant' ],
         {},
       ],
       [
         { 0 => 'in', 1 => $RE{number}, 2 => qr/^(days?)$/i },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [ [ 1 ] ],
         [ { unit => 'day' } ],
         [ '_in_count_variant' ],
         {},
       ],
       [
         { 0 => 'in', 1 => $RE{number}, 2 => qr/^(weeks?)$/i },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [ [ 1 ] ],
         [ { unit => 'week' } ],
         [ '_in_count_variant' ],
         {},
       ],
       [
         { 0 => 'in', 1 => $RE{number}, 2 => qr/^(months?)$/i },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [ [ 1 ] ],
         [ { unit => 'month' } ],
         [ '_in_count_variant' ],
         {},
       ],
       [
         { 0 => 'in', 1 => $RE{number}, 2 => qr/^(years?)$/i },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [ [ 1 ] ],
         [ { unit => 'year' } ],
         [ '_in_count_variant' ],
         {},
       ],
    ],
    count_weekday_variant_month => [
       [ 'REGEXP', 'REGEXP', 'REGEXP', 'REGEXP' ],
       [
         { 0 => $RE{day}, 1 => $RE{weekday}, 2 => qr/^(next)$/i, 3 => $RE{month} },
         [ [ 0 ] ],
         [ $extended_checks{ordinal} ],
         [
           [
             { 2 => [ $flag{last_this_next} ] },
               0,
             { 1 => [ $flag{weekday_name}, $flag{weekday_num} ] },
             { 3 => [ $flag{month_name}, $flag{month_num} ] },
           ],
         ],
         [ {} ],
         [ '_count_weekday_variant_month' ],
         { truncate_to => 'day' },
       ],
       [
         { 0 => $RE{day}, 1 => $RE{weekday}, 2 => qr/^(this)$/i, 3 => $RE{month} },
         [ [ 0 ] ],
         [ $extended_checks{ordinal} ],
         [
           [
             { 2 => [ $flag{last_this_next} ] },
               0,
             { 1 => [ $flag{weekday_name}, $flag{weekday_num} ] },
             { 3 => [ $flag{month_name}, $flag{month_num} ] },
           ],
         ],
         [ {} ],
         [ '_count_weekday_variant_month' ],
         { truncate_to => 'day' },
       ],
       [
         { 0 => $RE{day}, 1 => $RE{weekday}, 2 => qr/^(last)$/i, 3 => $RE{month} },
         [ [ 0 ] ],
         [ $extended_checks{ordinal} ],
         [
           [
             { 2 => [ $flag{last_this_next} ] },
               0,
             { 1 => [ $flag{weekday_name}, $flag{weekday_num} ] },
             { 3 => [ $flag{month_name}, $flag{month_num} ] },
           ],
         ],
         [ {} ],
         [ '_count_weekday_variant_month' ],
         { truncate_to => 'day' },
       ],
    ],
    daytime_hours_variant => [
       [ 'REGEXP', 'REGEXP', 'REGEXP', 'REGEXP' ],
       [
         { 0 => $RE{number}, 1 => qr/^(hours?)$/i, 2 => qr/^(before)$/i, 3 => qr/^(yesterday)$/i },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [
           [
               0,
             { 2 => [ $flag{before_after_from} ] },
             { 3 => [ $flag{yes_today_tom} ] },
           ],
         ],
         [ {} ],
         [ '_daytime_hours_variant' ],
         { truncate_to => 'hour' },
       ],
       [
         { 0 => $RE{number}, 1 => qr/^(hours?)$/i, 2 => qr/^(before)$/i, 3 => qr/^(tomorrow)$/i },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [
           [
               0,
             { 2 => [ $flag{before_after_from} ] },
             { 3 => [ $flag{yes_today_tom} ] },
           ],
         ],
         [ {} ],
         [ '_daytime_hours_variant' ],
         { truncate_to => 'hour' },
       ],
       [
         { 0 => $RE{number}, 1 => qr/^(hours?)$/i, 2 => qr/^(after)$/i, 3 => qr/^(yesterday)$/i },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [
           [
               0,
             { 2 => [ $flag{before_after_from} ] },
             { 3 => [ $flag{yes_today_tom} ] },
           ],
         ],
         [ {} ],
         [ '_daytime_hours_variant' ],
         { truncate_to => 'hour' },
       ],
       [
         { 0 => $RE{number}, 1 => qr/^(hours?)$/i, 2 => qr/^(after)$/i, 3 => qr/^(tomorrow)$/i },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [
           [
               0,
             { 2 => [ $flag{before_after_from} ] },
             { 3 => [ $flag{yes_today_tom} ] },
           ],
         ],
         [ {} ],
         [ '_daytime_hours_variant' ],
         { truncate_to => 'hour' },
       ],
    ],
    hourtime_before_variant => [
       [ 'REGEXP', 'REGEXP', 'REGEXP', 'SCALAR' ],
       [
         { 0 => $RE{number}, 1 => qr/^(hours?)$/i, 2 => qr/^(before)$/i, 3 => 'noon' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [
           [
               0,
             { 2 => [ $flag{before_after_from} ] },
           ],
         ],
         [ { hours => 12 } ],
         [ '_hourtime_variant' ],
         { truncate_to => 'hour' },
       ],
       [
         { 0 => $RE{number}, 1 => qr/^(hours?)$/i, 2 => qr/^(before)$/i, 3 => 'midnight' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [
           [
               0,
             { 2 => [ $flag{before_after_from} ] },
           ],
         ],
         [ {} ],
         [ '_hourtime_variant' ],
         { truncate_to => 'hour' },
       ],
       [
         { 0 => $RE{number}, 1 => qr/^(hours?)$/i, 2 => qr/^(after)$/i, 3 => 'noon' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [
           [
               0,
             { 2 => [ $flag{before_after_from} ] },
           ],
         ],
         [ { hours => 12 } ],
         [ '_hourtime_variant' ],
         { truncate_to => 'hour' },
       ],
       [
         { 0 => $RE{number}, 1 => qr/^(hours?)$/i, 2 => qr/^(after)$/i, 3 => 'midnight' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [
           [
               0,
             { 2 => [ $flag{before_after_from} ] },
           ],
         ],
         [ {} ],
         [ '_hourtime_variant' ],
         { truncate_to => 'hour' },
       ],
    ],
    day_am_pm => [
       [ 'REGEXP', 'REGEXP' ],
       [
         { 0 => qr/^(yesterday)$/i, 1 => $RE{time} },
         [],
         [],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [ 1 ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_time' ],
         { truncate_to => 'minute' },
       ],
       [
         { 0 => qr/^(today)$/i, 1 => $RE{time} },
         [],
         [],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [ 1 ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_time' ],
         { truncate_to => 'minute' },
       ],
       [
         { 0 => qr/^(tomorrow)$/i, 1 => $RE{time} },
         [],
         [],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [ 1 ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_time' ],
         { truncate_to => 'minute' },
       ],
       [
         { 0 => qr/^(yesterday)$/i, 1 => $RE{time_am} },
         [ [ 1 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 1 => [ $flag{time_am} ] },
           ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_at' ],
         { truncate_to => 'minute' },
       ],
       [
         { 0 => qr/^(today)$/i, 1 => $RE{time_am} },
         [ [ 1 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 1 => [ $flag{time_am} ] },
           ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_at' ],
         { truncate_to => 'minute' },
       ],
       [
         { 0 => qr/^(tomorrow)$/i, 1 => $RE{time_am} },
         [ [ 1 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 1 => [ $flag{time_am} ] },
           ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_at' ],
         { truncate_to => 'minute' },
       ],
       [
         { 0 => qr/^(yesterday)$/i, 1 => $RE{time_pm} },
         [ [ 1 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 1 => [ $flag{time_pm} ] },
           ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_at' ],
         { truncate_to => 'minute' },
       ],
       [
         { 0 => qr/^(today)$/i, 1 => $RE{time_pm} },
         [ [ 1 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 1 => [ $flag{time_pm} ] },
           ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_at' ],
         { truncate_to => 'minute' },
       ],
       [
         { 0 => qr/^(tomorrow)$/i, 1 => $RE{time_pm} },
         [ [ 1 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 1 => [ $flag{time_pm} ] },
           ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_at' ],
         { truncate_to => 'minute' },
       ],
    ],
    day_time => [
       [ 'REGEXP', 'SCALAR', 'REGEXP' ],
       [
         { 0 => qr/^(yesterday)$/i, 1 => 'at', 2 => $RE{time} },
         [],
         [],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [ 2 ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_time' ],
         { truncate_to => 'minute' },
       ],
       [
         { 0 => qr/^(today)$/i, 1 => 'at', 2 => $RE{time} },
         [],
         [],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [ 2 ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_time' ],
         { truncate_to => 'minute' },
       ],
       [
         { 0 => qr/^(tomorrow)$/i, 1 => 'at', 2 => $RE{time} },
         [],
         [],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [ 2 ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_time' ],
         { truncate_to => 'minute' },
       ],
       [
         { 0 => qr/^(yesterday)$/i, 1 => 'at', 2 => $RE{time_am} },
         [ [ 2 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 2 => [ $flag{time_am} ] },
           ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_at' ],
         { truncate_to => 'minute' },
       ],
       [
         { 0 => qr/^(today)$/i, 1 => 'at', 2 => $RE{time_am} },
         [ [ 2 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 2 => [ $flag{time_am} ] },
           ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_at' ],
         { truncate_to => 'minute' },
       ],
       [
         { 0 => qr/^(tomorrow)$/i, 1 => 'at', 2 => $RE{time_am} },
         [ [ 2 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 2 => [ $flag{time_am} ] },
           ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_at' ],
         { truncate_to => 'minute' },
       ],
    ],
    day_at_time => [
       [ 'REGEXP', 'SCALAR', 'REGEXP', 'SCALAR' ],
       [
         { 0 => qr/^(yesterday)$/i, 1 => 'at', 2 => $RE{time}, 3 => 'am' },
         [ [ 2 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 2 => [ $flag{time_am} ] },
           ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_at' ],
         { truncate_to => 'minute' },
       ],
       [
         { 0 => qr/^(today)$/i, 1 => 'at', 2 => $RE{time}, 3 => 'am' },
         [ [ 2 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 2 => [ $flag{time_am} ] },
           ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_at' ],
         { truncate_to => 'minute' },
       ],
       [
         { 0 => qr/^(tomorrow)$/i, 1 => 'at', 2 => $RE{time}, 3 => 'am' },
         [ [ 2 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 2 => [ $flag{time_am} ] },
           ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_at' ],
         { truncate_to => 'minute' },
       ],
       [
         { 0 => qr/^(yesterday)$/i, 1 => 'at', 2 => $RE{time}, 3 => 'pm' },
         [ [ 2 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 2 => [ $flag{time_pm} ] },
           ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_at' ],
         { truncate_to => 'minute' },
       ],
       [
         { 0 => qr/^(today)$/i, 1 => 'at', 2 => $RE{time}, 3 => 'pm' },
         [ [ 2 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 2 => [ $flag{time_pm} ] },
           ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_at' ],
         { truncate_to => 'minute' },
       ],
       [
         { 0 => qr/^(tomorrow)$/i, 1 => 'at', 2 => $RE{time}, 3 => 'pm' },
         [ [ 2 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 2 => [ $flag{time_pm} ] },
           ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_at' ],
         { truncate_to => 'minute' },
       ],
    ],
    weekday_at_time => [
       [ 'REGEXP', 'SCALAR', 'REGEXP' ],
       [
         { 0 => $RE{weekday}, 1 => 'at', 2 => $RE{time} },
         [],
         [],
         [
           [
             { 0 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
           [ 2 ],
         ],
         [ {}, {} ],
         [ '_weekday', '_time' ],
         {
           prefer_future => true,
           truncate_to   => 'minute',
         },
       ],
       [
         { 0 => $RE{weekday}, 1 => 'at', 2 => $RE{time_am} },
         [ [ 2 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
           [
             { 2 => [ $flag{time_am} ] },
           ],
         ],
         [ {}, {} ],
         [ '_weekday', '_at' ],
         {
           prefer_future => true,
           truncate_to   => 'minute',
         },
       ],
       [
         { 0 => $RE{weekday}, 1 => 'at', 2 => $RE{time_pm} },
         [ [ 2 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
           [
             { 2 => [ $flag{time_pm} ] },
           ],
         ],
         [ {}, {} ],
         [ '_weekday', '_at' ],
         {
           prefer_future => true,
           truncate_to   => 'minute',
         },
       ],
    ],
    time_on_weekday => [
       [ 'REGEXP', 'SCALAR', 'REGEXP' ],
       [
         { 0 => $RE{time}, 1 => 'on', 2 => $RE{weekday} },
         [],
         [],
         [
           [ 0 ],
           [
             { 2 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {}, {} ],
         [ '_time', '_weekday' ],
         {
           prefer_future => true,
           truncate_to   => 'minute',
         },
       ],
       [
         { 0 => $RE{time_am}, 1 => 'on', 2 => $RE{weekday} },
         [ [ 0 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{time_am} ] },
           ],
           [
             { 2 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {}, {} ],
         [ '_at', '_weekday' ],
         {
           prefer_future => true,
           truncate_to   => 'minute',
         },
       ],
       [
         { 0 => $RE{time_pm}, 1 => 'on', 2 => $RE{weekday} },
         [ [ 0 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{time_pm} ] },
           ],
           [
             { 2 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {}, {} ],
         [ '_at', '_weekday' ],
         {
           prefer_future => true,
           truncate_to   => 'minute',
         },
       ],
    ],
    weekday_at_am_pm => [
       [ 'REGEXP', 'SCALAR', 'REGEXP', 'SCALAR' ],
       [
         { 0 => $RE{weekday}, 1 => 'at', 2 => $RE{time}, 3 => 'am' },
         [ [ 2 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
           [
             { 2 => [ $flag{time_am} ] },
           ],
         ],
         [ {}, {} ],
         [ '_weekday', '_at' ],
         {
           prefer_future => true,
           truncate_to   => 'minute',
         },
       ],
       [
         { 0 => $RE{weekday}, 1 => 'at', 2 => $RE{time}, 3 => 'pm' },
         [ [ 2 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
           [
             { 2 => [ $flag{time_pm} ] },
           ],
         ],
         [ {}, {} ],
         [ '_weekday', '_at' ],
         {
           prefer_future => true,
           truncate_to   => 'minute',
         },
       ],
    ],
    weekday_am_pm => [
       [ 'REGEXP', 'REGEXP', 'SCALAR' ],
       [
         { 0 => $RE{weekday}, 1 => $RE{time}, 2 => 'am' },
         [ [ 1 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
           [
             { 1 => [ $flag{time_am} ] },
           ],
         ],
         [ {}, {} ],
         [ '_weekday', '_at' ],
         {
           prefer_future => true,
           truncate_to   => 'minute',
         },
       ],
       [
         { 0 => $RE{weekday}, 1 => $RE{time}, 2 => 'pm' },
         [ [ 1 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
           [
             { 1 => [ $flag{time_pm} ] },
           ],
         ],
         [ {}, {} ],
         [ '_weekday', '_at' ],
         {
           prefer_future => true,
           truncate_to   => 'minute',
         },
       ],
    ],
    day_at_pm => [
       [ 'REGEXP', 'SCALAR', 'REGEXP' ],
       [
         { 0 => qr/^(yesterday)$/i, 1 => 'at', 2 => $RE{time_pm} },
         [ [ 2 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 2 => [ $flag{time_pm} ] },
           ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_at' ],
         { truncate_to => 'minute' },
       ],
       [
         { 0 => qr/^(today)$/i, 1 => 'at', 2 => $RE{time_pm} },
         [ [ 2 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 2 => [ $flag{time_pm} ] },
           ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_at' ],
         { truncate_to => 'minute' },
       ],
       [
         { 0 => qr/^(tomorrow)$/i, 1 => 'at', 2 => $RE{time_pm} },
         [ [ 2 ] ],
         [ $extended_checks{meridiem} ],
         [
           [
             { 0 => [ $flag{yes_today_tom} ] },
           ],
           [
             { 2 => [ $flag{time_pm} ] },
           ],
         ],
         [ { unit => 'day' }, {} ],
         [ '_unit_variant', '_at' ],
         { truncate_to => 'minute' },
       ],
    ],
    day_month_year => [
       [ 'REGEXP', 'REGEXP', 'REGEXP' ],
       [
         { 0 => $RE{monthday}, 1 => $RE{month}, 2 => $RE{year} },
         [ [ 0 ] ],
         [ $extended_checks{ordinal} ],
         [
           [
               0,
             { 1 => [ $flag{month_name}, $flag{month_num} ] },
               2,
           ],
         ],
         [ {} ],
         [ '_day_month_year' ],
         { truncate_to => 'day' },
       ],
       [
         { 0 => $RE{month}, 1 => $RE{monthday}, 2 => $RE{year} },
         [ [ 1 ] ],
         [ $extended_checks{ordinal} ],
         [
           [
               1,
             { 0 => [ $flag{month_name}, $flag{month_num} ] },
               2,
           ],
         ],
         [ {} ],
         [ '_day_month_year' ],
         { truncate_to => 'day' },
       ],
    ],
    count_weekday_in_month => [
       [ 'REGEXP', 'REGEXP', 'SCALAR', 'REGEXP' ],
       [
         { 0 => $RE{day}, 1 => $RE{weekday}, 2 => 'in', 3 => $RE{month} },
         [ [ 0 ] ],
         [ $extended_checks{ordinal} ],
         [
           [
             { VALUE => 0 },
               0,
             { 1 => [ $flag{weekday_name}, $flag{weekday_num} ] },
             { 3 => [ $flag{month_name}, $flag{month_num} ] },
           ],
         ],
         [ {} ],
         [ '_count_weekday_variant_month' ],
         { truncate_to => 'day' },
       ],
    ],
    count_weekday_from_now => [
       [ 'REGEXP', 'REGEXP', 'SCALAR', 'SCALAR' ],
       [
         { 0 => $RE{number}, 1 => $RE{weekdays}, 2 => 'from', 3 => 'now' },
         [ [ 0, 1 ] ],
         [ $extended_checks{suffix} ],
         [
           [
               0,
             { 1 => [ $flag{weekday_name}, $flag{weekday_num} ] },
           ],
         ],
         [ {} ],
         [ '_count_weekday_from_now' ],
         { truncate_to => 'day' },
       ],
    ],
    final_weekday_in_month => [
       [ 'SCALAR', 'REGEXP', 'SCALAR', 'REGEXP' ],
       [
         { 0 => 'final', 1 => $RE{weekday}, 2 => 'in', 3 => $RE{month} },
         [],
         [],
         [
           [
             { 1 => [ $flag{weekday_name}, $flag{weekday_num} ] },
             { 3 => [ $flag{month_name}, $flag{month_num} ] },
           ],
         ],
         [ {} ],
         [ '_final_weekday_in_month' ],
         { truncate_to => 'day' },
       ],
       [
         { 0 => 'last', 1 => $RE{weekday}, 2 => 'in', 3 => $RE{month} },
         [],
         [],
         [
           [
             { 1 => [ $flag{weekday_name}, $flag{weekday_num} ] },
             { 3 => [ $flag{month_name}, $flag{month_num} ] },
           ],
         ],
         [ {} ],
         [ '_final_weekday_in_month' ],
         { truncate_to => 'day' },
       ],
    ],
    for_count_unit => [
       [ 'SCALAR', 'REGEXP', 'REGEXP' ],
       [
         { 0 => 'for', 1 => $RE{number}, 2 => qr/^(seconds?)$/i },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [ 1 ],
         ],
         [ { unit => 'second' } ],
         [ '_in_count_variant' ],
         {},
       ],
       [
         { 0 => 'for', 1 => $RE{number}, 2 => qr/^(minutes?)$/i },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [ 1 ],
         ],
         [ { unit => 'minute' } ],
         [ '_in_count_variant' ],
         {},
       ],
       [
         { 0 => 'for', 1 => $RE{number}, 2 => qr/^(hours?)$/i },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [ 1 ],
         ],
         [ { unit => 'hour' } ],
         [ '_in_count_variant' ],
         {},
       ],
       [
         { 0 => 'for', 1 => $RE{number}, 2 => qr/^(days?)$/i },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [ 1 ],
         ],
         [ { unit => 'day' } ],
         [ '_in_count_variant' ],
         {},
       ],
       [
         { 0 => 'for', 1 => $RE{number}, 2 => qr/^(weeks?)$/i },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [ 1 ],
         ],
         [ { unit => 'week' } ],
         [ '_in_count_variant' ],
         {},
       ],
       [
         { 0 => 'for', 1 => $RE{number}, 2 => qr/^(months?)$/i },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [ 1 ],
         ],
         [ { unit => 'month' } ],
         [ '_in_count_variant' ],
         {},
       ],
       [
         { 0 => 'for', 1 => $RE{number}, 2 => qr/^(years?)$/i },
         [ [ 1, 2 ] ],
         [ $extended_checks{suffix} ],
         [
           [ 1 ],
         ],
         [ { unit => 'year' } ],
         [ '_in_count_variant' ],
         {},
       ],
    ],
    first_last_day_unit => [
       [ 'SCALAR', 'SCALAR', 'SCALAR', 'REGEXP' ],
       [
         { 0 => 'first', 1 => 'day', 2 => 'of', 3 => $RE{month} },
         [],
         [],
         [
           [
             { 3 => [ $flag{month_name}, $flag{month_num} ] },
             { VALUE => 1 },
           ],
         ],
         [ {} ],
         [ '_first_last_day_unit' ],
         { truncate_to => 'day' },
       ],
       [
         { 0 => 'first', 1 => 'day', 2 => 'of', 3 => $RE{year} },
         [],
         [],
         [
           [
               3,
             { VALUE => 1 },
             { VALUE => 1 },
           ],
         ],
         [ {} ],
         [ '_first_last_day_unit' ],
         { truncate_to => 'day' },
       ],
       [
         { 0 => 'last', 1 => 'day', 2 => 'of', 3 => $RE{month} },
         [],
         [],
         [
           [
             { 3 => [ $flag{month_name}, $flag{month_num} ] },
             { VALUE => undef },
           ],
         ],
         [ {} ],
         [ '_first_last_day_unit' ],
         { truncate_to => 'day' },
       ],
       [
         { 0 => 'last', 1 => 'day', 2 => 'of', 3 => $RE{year} },
         [],
         [],
         [
           [
                3,
              { VALUE => 12 },
              { VALUE => undef },
            ],
         ],
         [ {} ],
         [ '_first_last_day_unit' ],
         { truncate_to => 'day' },
       ],
    ],
);

1;
__END__

=head1 DESCRIPTION

C<DateTime::Format::Natural::Lang::ID> provides the Indonesian specific grammar
and variables. This class is loaded if the user specifies the Indonesian
language.

=head1 EXAMPLES

Below are some examples of human readable date/time input in Indonesian (be aware
that the parser does not distinguish between lower/upper case):

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

=head1 CREDITS

Based on L<DateTime::Format::Natural::Lang::EN> by Steven Schubiger.

=head1 SEE ALSO

L<DateTime::Format::Natural>

=cut
