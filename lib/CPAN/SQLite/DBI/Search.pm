package CPAN::SQLite::DBI::Search;
use base qw(CPAN::SQLite::DBI);
use CPAN::SQLite::DBI qw($tables $dbh);
use CPAN::SQLite::Util qw($full_id);

our $VERSION = '0.1_03';

use strict;
use warnings;

package CPAN::SQLite::DBI::Search::chaps;
use base qw(CPAN::SQLite::DBI::Search);
use CPAN::SQLite::DBI qw($dbh);

package CPAN::SQLite::DBI::Search::mods;
use base qw(CPAN::SQLite::DBI::Search);
use CPAN::SQLite::DBI qw($dbh);

package CPAN::SQLite::DBI::Search::dists;
use base qw(CPAN::SQLite::DBI::Search);
use CPAN::SQLite::DBI qw($dbh);

package CPAN::SQLite::DBI::Search::auths;
use base qw(CPAN::SQLite::DBI::Search);
use CPAN::SQLite::DBI qw($dbh);

package CPAN::SQLite::DBI::Search;
use base qw(CPAN::SQLite::DBI);
use CPAN::SQLite::DBI qw($tables $dbh);
use CPAN::SQLite::Util qw($full_id expand_dslip download %chaps);

sub fetch {
  my ($self, %args) = @_;
  my $fields = $args{fields};
  my $search = $args{search};
  my @fields = ref($fields) eq 'ARRAY' ? 
    @{$fields} : ($fields);
  my $sql = $self->sql_statement(%args) or do {
    $self->{error} = 'Error constructing sql statement: ' .
      $self->{error};
    return;
  };
  my $sth = $dbh->prepare($sql) or do {
    $self->db_error();
    return;
  };
  $sth->execute();

  if (not $search->{wantarray}) {
    my (%results, %meta_results);
    @results{@fields} = $sth->fetchrow_array;
    $sth->finish;
    return if $sth->rows == 0;
    $self->extra_info(\%results);
    undef $sth;
    return \%results;
  }
  else {
    my (%hash, $results);
    while ( @hash{@fields} = $sth->fetchrow_array) {
      my %tmp = %hash;
      $self->extra_info(\%tmp);
      push @{$results}, \%tmp;
    }
    $sth->finish;
    return if $sth->rows == 0;
    undef $sth;
    return $results;
  }
}

sub fetch_and_set {
  my ($self, %args) = @_;
  my $fields = $args{fields};
  my $search = $args{search};
  my $meta_obj = $args{meta_obj};
  die "Please supply a CPAN::SQLite::Meta::* object"
    unless ($meta_obj and ref($meta_obj) =~ /^CPAN::SQLite::META/);
  my @fields = ref($fields) eq 'ARRAY' ? 
    @{$fields} : ($fields);
  my $sql = $self->sql_statement(%args) or do {
    $self->{error} = 'Error constructing sql statement: ' .
      $self->{error};
    return;
  };
  my $sth = $dbh->prepare($sql) or do {
    $self->db_error();
    return;
  };
  $sth->execute();

  my $want_ids = $args{want_ids};
  my $set_list = $args{set_list};
  if (not $search->{wantarray}) {
    my (%results, %meta_results);
    @results{@fields} = $sth->fetchrow_array;
    $sth->finish;
    return if $sth->rows == 0;
    $self->extra_info(\%results);
    $meta_obj->set_data(\%results);
    undef $sth;
    if ($want_ids) {
      $meta_results{$search->{id}} = $results{$search->{id}};
      return \%meta_results;
    }
    else {
      return 1;
    }
  }
  else {
    my (%hash, $meta_results);
    while ( @hash{@fields} = $sth->fetchrow_array) {
      my %tmp = %hash;
      if ($set_list) {
	push @{$meta_results}, \%tmp;
      }
      else {
	$self->extra_info(\%tmp);
	$meta_obj->set_data(\%tmp);	
	if ($want_ids) {
	  push @{$meta_results}, {$search->{id} => $tmp{$search->{id}}};
	}
      }
    }
    $sth->finish;
    return if $sth->rows == 0;
    undef $sth;
    $meta_obj->set_list_data($meta_results) if $set_list;
    return $want_ids ? $meta_results : 1;
  }
}

sub extra_info {
  my ($self, $results) = @_;
  if ($results->{cpanid} and $results->{dist_file}) {
    $results->{download} = download($results->{cpanid}, $results->{dist_file});
  }
  my $what;
  if ( ($what = $results->{dslip}) or ($what = $results->{dist_dslip}) ) {
    $results->{dslip_info} = expand_dslip($what);
  }
  if (my $chapterid = $results->{chapterid}) {
    $chapterid += 0;
    $results->{chapter_desc} = $chaps{$chapterid};
  }
}

sub sql_statement {
  my ($self, %args) = @_;

  my $search = $args{search};
  my $distinct = $search->{distinct} ? 'DISTINCT' : '';
  my $table = $args{table};
  my @tables = ($table);

  my $fields = $args{fields};
  my @fields = ref($fields) eq 'ARRAY' ? 
    @{$fields} : ($fields);
  for (@fields) {
    $_ = $full_id->{$_} if $full_id->{$_};
  }

  my $sql = qq{SELECT $distinct } . join(',', @fields);
  my $where = '';
  my $type = $search->{type};
 QUERY: {
    ($type eq 'query' ) and do {
      my $value = $search->{value};
      last QUERY if ($value eq '^');
      my $name = $search->{name};
      my $text = $search->{text};
      my $use_like = ($value =~ /^\^?[A-Za-z0-9_\\\:\-]+$/) ? 1 : 0;
      my $prepend = '%';
      if ($use_like and $value =~ /^\^/) {
	$prepend = '';
	$value =~ s/^\^//;
	$value =~ s{\\}{}g;
      }
      $where = $use_like ?
	qq{$name LIKE '$prepend$value%'} : 
	  qq{RLIKE($name, '$value')};
      if ($name eq 'cpanid') {
	$where .= $use_like ?
	  qq{ OR $text LIKE '$prepend$value%'} : 
	    qq{ OR RLIKE($text, '$value')};
      }
      last QUERY;
    };
    ($type eq 'id') and do {
      $where = qq{ $search->{id} = $search->{value} };
      last QUERY;
    };
    ($type eq 'name') and do {
      $where = qq{ $search->{name} = '$search->{value}' };
      last QUERY;
    };
    warn qq{Unknown query type};
    return;
  }
  my $join;

  $sql .= ' FROM ' . $table;
  my $left_join = $args{join} || $args{left_join};
  if ($left_join) {
    if (ref($left_join) eq 'HASH') {
      foreach my $key(keys %$left_join) {
	my $id = $left_join->{$key};
	$sql .= " LEFT JOIN $key ON $table.$id=$key.$id ";
      }
    }
  }

  if ($where) {
    $sql .= ' WHERE ( ' . $where . ' )';
    $sql .= ' AND (' . $join . ')' if $join;
  }
  else {
    $sql .= ' WHERE (' . $join . ')' if $join;
  }

  my $order_by = '';
  if (my $user_order_by = $args{order_by}) {
    $order_by = $order_by ? "$order_by,$user_order_by" : $user_order_by;
  }
  if ($order_by and $where) {
    $sql .= qq{ ORDER BY $order_by };
  }

  if (my $limit = $args{limit}) {
    my ($min, $max) = ref($limit) eq 'HASH' ?
      ( $limit->{min} || 0, $limit->{max} ) :
	(0, $limit );
    $sql .= qq{ LIMIT $min,$max };
  }
  return $sql;
}

1;

__END__

=head1 NAME

CPAN::SQLite::DBI::Search - DBI information for searching the CPAN::SQLite database

=head1 DESCRIPTION

This module provides methods for L<CPAN::SQLite::Search> for searching
the C<CPAN::SQLite> database. There are two main methods.

=over

=item C<fetch>

This takes information from C<CPAN::SQLite::Search> and sets up
a query on the database, returning the results found.

=item C<sql_statement>

This is used by the C<fetch> method to construct the appropriate
SQL statement.

=back

=head1 SEE ALSO

L<CPAN::SQLite::Search>

=cut