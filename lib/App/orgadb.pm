package App::orgadb;

use 5.010001;
use strict;
use warnings;

# AUTHORITY
# DATE
# DIST
# VERSION

our %SPEC;

$SPEC{':package'} = {
    v => 1.1,
    summary => 'An opinionated Org addressbook tool',
};

our %argspecs_common = (
    files => {
        summary => 'Path to addressbook files',
        'summary.alt.plurality.singular' => 'Path to addressbook file',
        'x.name.is_plural' => 1,
        'x.name.singular' => 'file',
        schema => ['array*', of=>'filename*', min_len=>1],
        tags => ['category:input'],
    },
);

our %argspec_entry = (
    entry => {
        summary => 'Find entry by string or regex search against its title',
        schema => 'str_or_regex',
    },
);

$SPEC{select_addressbook_entries} = {
    v => 1.1,
    summary => 'Select Org document elements using CSel (CSS-selector-like) syntax',
    args => {
        %argspecs_common,
        %argspec_entry,
    },
};
sub orgsel {
     App::CSelUtils::foosel(
        @_,

        code_read_tree => sub {
            require Org::Parser;
            my $args = shift;

            my $parser = Org::Parser->new;
            my $doc;
            if ($args->{file} eq '-') {
                binmode STDIN, ":encoding(utf8)";
                $doc = $parser->parse(join "", <>);
            } else {
                local $ENV{PERL_ORG_PARSER_CACHE} = $ENV{PERL_ORG_PARSER_CACHE} // 1;
                $doc = $parser->parse_file($args->{file});
            }
        },

        csel_opts => {class_prefixes=>["Org::Element"]},

        code_transform_node_actions => sub {
            my $args = shift;

            for my $action (@{$args->{node_actions}}) {
                if ($action eq 'dump') {
                    $action = 'dump:as_string';
                }
            }
        },
    );
}

1;
#ABSTRACT:

=head1 SYNOPSIS
