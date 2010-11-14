package Moo::Role;

use strictures 1;
use Moo::_Utils;
use base qw(Role::Tiny);

BEGIN { *INFO = \%Role::Tiny::INFO }

our %INFO;

sub import {
  my $target = caller;
  strictures->import;
  return if $INFO{$target}; # already exported into this package
  # get symbol table reference
  my $stash = do { no strict 'refs'; \%{"${target}::"} };
  *{_getglob "${target}::has"} = sub {
    my ($name, %spec) = @_;
    ($INFO{$target}{accessor_maker} ||= do {
      require Method::Generate::Accessor;
      Method::Generate::Accessor->new
    })->generate_method($target, $name, \%spec);
    $INFO{$target}{attributes}{$name} = \%spec;
  };
  goto &Role::Tiny::import;
}

sub apply_role_to_package {
  my ($me, $role, $to) = @_;
  $me->SUPER::apply_role_to_package($role, $to);
  $me->_handle_constructor($to, $INFO{$role}{attributes});
}

sub create_class_with_roles {
  my ($me, $superclass, @roles) = @_;

  my $new_name = join('+', $superclass, my $compose_name = join '+', @roles);
  return $new_name if $Role::Tiny::COMPOSED{class}{$new_name};

  require Sub::Quote;

  $me->SUPER::create_class_with_roles($superclass, @roles);

  foreach my $role (@roles) {
    die "${role} is not a Role::Tiny" unless my $info = $INFO{$role};
  }

  $me->_handle_constructor(
    $new_name, { map %{$INFO{$_}{attributes}||{}}, @roles }
  );

  return $new_name;
}

sub _install_single_modifier {
  my ($me, @args) = @_;
  _install_modifier(@args);
}

sub _handle_constructor {
  my ($me, $to, $attr_info) = @_;
  return unless $attr_info && keys %$attr_info;
  if ($INFO{$to}) {
    @{$INFO{$to}{attributes}||={}}{keys %$attr_info} = values %$attr_info;
  } else {
    # only fiddle with the constructor if the target is a Moo class
    if ($INC{"Moo.pm"}
        and my $con = Moo->_constructor_maker_for($to)) {
      $con->register_attribute_specs(%$attr_info);
    }
  }
}

1;

=pod

=head1 SYNOPSIS

 package My::Role;

 use Moo::Role;

 sub foo { ... }

 sub bar { ... }

 has baz => (
   is => 'ro',
 );

 1;

else where

 package Some::Class;

 use Moo;

 # bar gets imported, but not foo
 with('My::Role');

 sub foo { ... }

 1;

=head1 DESCRIPTION

C<Moo::Role> builds upon L<Role::Tiny>, so look there for most of the
documentation on how this works.  The main addition here is extra bits to make
the roles more "Moosey;" which is to say, it adds L</has>.

=head1 IMPORTED SUBROUTINES

See L<Role::Tiny/IMPORTED SUBROUTINES> for all the other subroutines that are
imported by this module.

=head2 has

 has attr => (
   is => 'ro',
 );

Declares an attribute for the class to be composed into.  See
L<Moo/has> for all options.