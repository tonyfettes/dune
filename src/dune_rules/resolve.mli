(** Library name resolution monad *)

(** The goal of the [Resolve] monad is to delay library related errors until we
    actually need the result.

    Indeed, in many places in the Dune codebase we eagerly resolve library names
    at "rule generation time". This means that if a library was missing, we
    could fail right from the start if we are not careful. What is more, we
    would fail even if we didn't need to build the item that depended on this
    library. This would not be good.

    This is where the [Resolve] monad can help. A [_ Resolve.t] value represent
    a computation that resolved some library names and might have failed. The
    failure is captured in the [Resolve.t] value. Failures will be propagated
    when we "read" a [Resolve.t].

    {2 Reading resolve values}

    You should use [read] or [args] on [Resolve.t] values inside code that
    compute the action of a rule. By doing so, any error will be propagated only
    at the point where the rule is actually being executed. For instance:

    {[
      add_rule
        (let open Action_builder.O in
        let* libs = Resolve.read requires in
        gen_action libs)
    ]}

    or:

    {[
      Command.run prog
        [ Resolve.args
            (let open Resolve.O in
            let+ libs = Resolve.args requires in
            Command.Args.S [ gen_args libs ])
        ]
    ]}

    {2 Reading resolve values early}

    It is sometimes necessary to read a [Resolve.t] value at rule generation
    time. For instance, it is necessary to do that for setting the rule for
    inline tests. This is because some information needed to setup the rules are
    attached to the backend library for the inline test framework.

    One way to do that would be to call [read_memo] while setting up the rules:

    {[
      let open Memo.O in
      let* libs = Resolve.get libs in
      gen_rules libs
    ]}

    However, as discussed earlier this would cause Dune to fail too early and
    too often. There are two ways to deal with this:

    1. refactor the code so that only [Resolve.read] and/or [Resolve.args] are
    used from inside the code that compute rules actions

    2. use [Resolve.peek] and produce the rules using some dummy value in the
    error case

    1 is generally the cleaner solution but requires more work. 2 is a quick fix
    to still generates some rules and fail when rules are actually being
    executed. For instance:

    {[
      let libs =
        match Resolve.peek libs with
        | Ok x -> x
        | Error () -> []
        (* or a dummy value *)
      in
      gen_rules libs
    ]}

    If you use this pattern, you need to make sure that the rules will indeed
    fail with the error captured in the [libs] value.
    [Action_builder.prefix_rules] provides a hassle free way to do this,
    allowing one to "inject" a failure in each rule generated by a piece of
    code. In the end the code should looking this this:

    {[
      match Resolve.peek libs with
      | Ok libs -> gen_rules libs
      | Error () ->
        let fail = Action_builder.ignore (Resolve.read libs) in
        Rules.prefix_rules fail ~f:(fun () -> gen_rules libs)
    ]} *)

open Import

type 'a t

include Monad.S with type 'a t := 'a t

val equal : ('a -> 'a -> bool) -> 'a t -> 'a t -> bool

val hash : ('a -> int) -> 'a t -> int

val to_dyn : ('a -> Dyn.t) -> 'a t Dyn.builder

val of_result : ('a, exn) result -> 'a t

type error

val to_result : 'a t -> ('a, error) result

val of_error : error -> 'a t

(** Read a [Resolve.t] value inside the action builder monad. *)
val read : 'a t -> 'a Action_builder.t

(** [args] allows to easily inject a resolve monad computing some command line
    arguments into an command line specification. *)
val args : 'a Command.Args.t t -> 'a Command.Args.t

(** Same as [read] but in the memo build monad. Use with caution! *)
val read_memo : 'a t -> 'a Memo.t

(** Read the value immediately, ignoring actual errors. *)
val peek : 'a t -> ('a, unit) result

(** [is_ok t] is the same as [Result.is_ok (peek t)] *)
val is_ok : 'a t -> bool

(** [is_ok t] is the same as [Result.is_error (peek t)] *)
val is_error : 'a t -> bool

(** When in the resolve monad, you should prefer using this function rather than
    raising directly. This allows errors to be delayed until the monad is
    actually evaluated. *)
val fail : User_message.t -> _ t

(** Similar to [Memo.push_stack_frame]. *)
val push_stack_frame :
  human_readable_description:(unit -> User_message.Style.t Pp.t) -> 'a t -> 'a t

val all : 'a t list -> 'a list t

module List : sig
  val map : 'a list -> f:('a -> 'b t) -> 'b list t

  val filter_map : 'a list -> f:('a -> 'b option t) -> 'b list t

  val concat_map : 'a list -> f:('a -> 'b list t) -> 'b list t

  val iter : 'a list -> f:('a -> unit t) -> unit t

  val fold_left : 'a list -> f:('acc -> 'a -> 'acc t) -> init:'acc -> 'acc t
end

module Option : sig
  val iter : 'a option -> f:('a -> unit t) -> unit t
end

module Memo : sig
  type 'a resolve := 'a t

  type 'a t = 'a resolve Memo.t

  val all : 'a t list -> 'a list t

  include Monad.S with type 'a t := 'a t

  val push_stack_frame :
       human_readable_description:(unit -> User_message.Style.t Pp.t)
    -> (unit -> 'a t)
    -> 'a t

  val lift_memo : 'a Memo.t -> 'a t

  val lift : 'a resolve -> 'a t

  val is_ok : 'a t -> bool Memo.t

  (** [is_ok t] is the same as [Result.is_error (peek t)] *)
  val is_error : 'a t -> bool Memo.t

  module List : Monad.List with type 'a t := 'a t

  module Option : sig
    val iter : 'a option -> f:('a -> unit t) -> unit t
  end

  (** Same as [read] but in the memo build monad. Use with caution! *)
  val read_memo : 'a t -> 'a Memo.t

  (** Read a [Resolve.t] value inside the action builder monad. *)
  val read : 'a t -> 'a Action_builder.t

  (** [args] allows to easily inject a resolve monad computing some command line
      arguments into an command line specification. *)
  val args : Command.Args.without_targets Command.Args.t t -> 'a Command.Args.t

  val fail : User_message.t -> _ t

  val of_result : ('a, exn) result -> 'a t

  (** Read the value immediately, ignoring actual errors. *)
  val peek : 'a t -> ('a, unit) result Memo.t
end
