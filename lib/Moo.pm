package Moo;

use strictures 1;
use Moo::_Utils;

our $VERSION = '0.009001'; # 0.9.1
$VERSION = eval $VERSION;

our %MAKERS;

sub import {
  my $target = caller;
  my $class = shift;
  strictures->import;
  return if $MAKERS{$target}; # already exported into this package
  *{_getglob("${target}::extends")} = sub {
    _load_module($_) for @_;
    *{_getglob("${target}::ISA")} = \@_;
  };
  *{_getglob("${target}::with")} = sub {
    require Moo::Role;
    die "Only one role supported at a time by with" if @_ > 1;
    Moo::Role->apply_role_to_package($_[0], $target);
  };
  $MAKERS{$target} = {};
  *{_getglob("${target}::has")} = sub {
    my ($name, %spec) = @_;
    ($MAKERS{$target}{accessor} ||= do {
      require Method::Generate::Accessor;
      Method::Generate::Accessor->new
    })->generate_method($target, $name, \%spec);
    $class->_constructor_maker_for($target)
          ->register_attribute_specs($name, \%spec);
  };
  foreach my $type (qw(before after around)) {
    *{_getglob "${target}::${type}"} = sub {
      require Class::Method::Modifiers;
      _install_modifier($target, $type, @_);
    };
  }
  {
    no strict 'refs';
    @{"${target}::ISA"} = do {
      require Moo::Object; ('Moo::Object');
    } unless @{"${target}::ISA"};
  }
}

sub _constructor_maker_for {
  my ($class, $target) = @_;
  return unless $MAKERS{$target};
  $MAKERS{$target}{constructor} ||= do {
    require Method::Generate::Constructor;
    Method::Generate::Constructor
      ->new(
        package => $target,
        accessor_generator => do {
          require Method::Generate::Accessor;
          Method::Generate::Accessor->new;
        }
      )
      ->install_delayed
      ->register_attribute_specs(do {
        my @spec;
        # using the -last- entry in @ISA means that classes created by
        # Role::Tiny as N roles + superclass will still get the attributes
        # from the superclass
        if (my $super = do { no strict 'refs'; ${"${target}::ISA"}[-1] }) {
          if (my $con = $MAKERS{$super}{constructor}) {
            @spec = %{$con->all_attribute_specs};
          }
        }
        @spec;
      });
  }
}

1;

=pod

=head1 SYNOPSIS

 package Cat::Food;

 use Moo;
 use Sub::Quote;

 sub feed_lion {
   my $self = shift;
   my $amount = shift || 1;

   $self->pounds( $self->pounds - $amount );
 }

 has taste => (
   is => 'ro',
 );

 has brand => (
   is  => 'ro',
   isa => sub {
     die "Only SWEET-TREATZ supported!" unless $_[0] eq 'SWEET-TREATZ'
   },
);

 has pounds => (
   is  => 'rw',
   isa => quote_sub q{ die "$_[0] is too much cat food!" unless $_[0] < 15 },
 );

 1;

and else where

 my $full = Cat::Food->new(
    taste  => 'DELICIOUS.',
    brand  => 'SWEET-TREATZ',
    pounds => 10,
 );

 $full->feed_lion;

 say $full->pounds;

=head1 DESCRIPTION

This module is an extremely light-weight, high-performance L<Moose> replacement.
It also avoids depending on any XS modules to allow simple deployments.  The
name C<Moo> is based on the idea that it provides almost -but not quite- two
thirds of L<Moose>.

Unlike C<Mouse> this module does not aim at full L<Moose> compatibility.  See
L</INCOMPATIBILITIES> for more details.

=head1 IMPORTED METHODS

=head2 new

 Foo::Bar->new( attr1 => 3 );

or

 Foo::Bar->new({ attr1 => 3 });

=head2 BUILDALL

Don't override (or probably even call) this method.  Instead, you can define
a C<BUILD> method on your class and the constructor will automatically call the
C<BUILD> method from parent down to child after the object has been
instantiated.  Typically this is used for object validation or possibly logging.

=head2 does

 if ($foo->does('Some::Role1')) {
   ...
 }

Returns true if the object composes in the passed role.

=head1 IMPORTED SUBROUTINES

=head2 extends

 extends 'Parent::Class';

Declares base class

=head2 with

 with 'Some::Role1';
 with 'Some::Role2';

Composes a L<Role::Tiny> into current class.  Only one role may be composed in
at a time to allow the code to remain as simple as possible.

=head2 has

 has attr => (
   is => 'ro',
 );

Declares an attribute for the class.

The options for C<has> are as follows:

=over 2

=item * is

B<required>, must be C<ro> or C<rw>.  Unsurprisingly, C<ro> generates an
accessor that will not respond to arguments; to be clear: a setter only. C<rw>
will create a perlish getter/setter.

=item * isa

Takes a coderef which is meant to validate the attribute.  Unlike L<Moose> Moo
does not include a basic type system, so instead of doing C<< isa => 'Num' >>,
one should do

 isa => quote_sub q{
   die "$_[0] is not a number!" unless looks_like_number $_[0]
 },

L<Sub::Quote aware|/SUB QUOTE AWARE>

=item * coerce

Takes a coderef which is meant to coerce the attribute.  The basic idea is to
do something like the following:

 coerce => quote_sub q{
   $_[0] + 1 unless $_[0] % 2
 },

L<Sub::Quote aware|/SUB QUOTE AWARE>

=item * trigger

Takes a coderef which will get called any time the attribute is set. Coderef
will be invoked against the object with the new value as an argument.

L<Sub::Quote aware|/SUB QUOTE AWARE>

=item * default

Takes a coderef which will get called to populate an attribute.

L<Sub::Quote aware|/SUB QUOTE AWARE>

=item * predicate

Takes a method name which will return true if an attribute has been set.

A common example of this would be to call it C<has_$foo>, implying that the
object has a C<$foo> set.

=item * builder

Takes a method name which will be called to create the attribute.

=item * clearer

Takes a method name which will clear the attribute.

=item * lazy

B<Boolean>.  Set this if you want values for the attribute to be grabbed
lazily.  This is usually a good idea if you have a L</builder> which requires
another attribute to be set.

=item * required

B<Boolean>.  Set this if the attribute must be passed on instantiation.

=item * weak_ref

B<Boolean>.  Set this if you want the reference that the attribute contains to
be weakened; use this when circular references are possible, which will cause
leaks.

=item * init_arg

Takes the name of the key to look for at instantiation time of the object.  A
common use of this is to make an underscored attribute have a non-underscored
initialization name. C<undef> means that passing the value in on instantiation

=back

=head2 before

 before foo => sub { ... };

See L<< Class::Method::Modifiers/before method(s) => sub { ... } >> for full
documentation.

=head2 around

 around foo => sub { ... };

See L<< Class::Method::Modifiers/around method(s) => sub { ... } >> for full
documentation.

=head2 after

 after foo => sub { ... };

See L<< Class::Method::Modifiers/after method(s) => sub { ... } >> for full
documentation.


=head1 SUB QUOTE AWARE

L<Sub::Quote/quote_sub> allows us to create coderefs that are "inlineable,"
giving us a handy, XS-free speed boost.  Any option that is L<Sub::Quote>
aware can take advantage of this.

=head1 INCOMPATIBILITIES

You can only compose one role at a time.  If your application is large or
complex enough to warrant complex composition, you wanted L<Moose>.

There is no complex type system.  C<isa> is verified with a coderef, if you
need complex types, just make a library of coderefs, or better yet, functions
that return quoted subs.

C<initializer> is not supported in core, but with an extension it is supported.

There is no meta object.  If you need this level of complexity you wanted
L<Moose>.

No support for C<super>, C<override>, C<inner>, or C<augment>.

L</default> only supports coderefs, because doing otherwise is usually a
mistake anyway.

C<lazy_build> is not supported per se, but of course it will work if you
manually set all the options it implies.

C<auto_deref> is not supported.

C<documentation> is not supported.