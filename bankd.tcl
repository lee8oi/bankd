namespace eval bankd {
################################################################################
#
#   Copyright ©2011 lee8oi@gmail.com
#
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#   http://www.gnu.org/licenses/
#
################################################################################
#
#   Bankd script v0.4.6 (9-29-11)
#   by: <lee8oi@github><lee8oiOnfreenode>
#   github link: https://github.com/lee8oi/bankd/blob/master/bankd.tcl
#
#   Bankd script is one of those 'wouldn't it be kinda cool if' ideas I came 
#   up with mainly to entertain myself. The idea was to come up with a
#   banking system that could be used for role playing purposes in selected
#   channels allowing users to transfer funds to other users and collect
#   interest.
#
#   The public command allows users to check thier balance or transfer
#   funds to another user (provided both have accounts). Bot owners 
#   have access to the dcc/partyline command '.bankd' which allows them to add,
#   remove, list, check, and edit the 'bank accounts'. An automatic timer 
#   periodically adds an 'interest' to all existing bank accounts.
#
#   ------------------------------------------------------------------------
#
#   Updates for v0.4:
#    1.Added configurable backupfile location/name.
#    2.Fixed nick case issue. User can now access account even if they
#    change the case of their nick.
#    3.Added public command trigger configuration. Fixed public command 
#    help to show command syntax using current trigger instead of default
#    trigger.
#    4.Added configurable public command trigger.
#    5.Switched pub_handler proc to use proper command bind instead of
#    checking all channel msgs for command trigger.
#    6.Minor code cleanup/commenting. Added 'log interest payouts' config
#    for enabling/disabling logging the interest payments paid on intervals.
#
#   ------------------------------------------------------------------------
#
#   Initial channel setup:
#   (enables use of public info command in specified channel)
#    .chanset #channel +bankd
#
#   Public command syntax:
#    .bank ?balance|transfer? ?args?
#
#   DCC (partyline) command syntax:
#    .bankd ?add|remove|check|list|edit? ?args?
#
#   Example Usage:
#    (public)
#       <lee8oi> !bank balance
#   <dukelovett> lee8oi, your balance is: 1000
#       <lee8oi> !bank transfer 100 dukelovett
#   <dukelovett> transfer successful.
#       <lee8oi> !bank
#   <dukelovett> usage: .bank ?balance|transfer? ?args?
#
#    (DCC/Partyline)
#       <lee8oi> .bankd add jimmy
#   <dukelovett> account created.
#       <lee8oi> .bankd remove jimmy
#   <dukelovett> account removed.
#       <lee8oi> .bankd
#   <dukelovett> usage: .bankd ?add|remove|check|list|edit? ?args?
#       <lee8oi> .bankd add
#   <dukelovett> usage: .bankd add <name>
#
################################################################################
#
#   CONFIGURATION
#   ------------------------------------------------------------------------
#   PUBLIC COMMAND TRIGGER
#    Sets the public command trigger used in channel to access bank account.
#                      +------+
    variable trigger    !bank
#                      +------+
#
#   INTEREST PERCENTAGE RATE
#    Bank balances are multiplied by this number to calculate amount of 
#    interest to be added to bank accounts at interest timer interval.
#                       +--+ 
    variable intrate    .01
#                       +--+
#
#   INTEREST TIMER INTERVAL
#    Number of minutes between timer intervals.
#                          +--+
    variable intinterval    10
#                          +--+
#
#   LOG INTEREST PAYOUTS
#    Uses putlog to log interest amounts paid each interval.
#    1=on 0=off
#                         +-+
    variable loginterest   0
#                         +-+
#
#   BACKUP LOCATION/FILE
#    Relative pathname starting from eggdrop dir. The location/filename of
#    the backup file used to save bank information.
#                         +----------------------+
    variable backupfile    "scripts/bankdb.tcl"
#                         +----------------------+
#
################################################################################
#   Experts only below.
################################################################################
}
bind pub - [set ::bankd::trigger] ::bankd::pub_handler
bind dcc n bankd ::bankd::dcc_admin
setudef flag bankd
namespace eval bankd {
    variable bankdb
    variable ver "0.4.6"
    if {[file exist [set ::bankd::backupfile]]} {
        source [set ::bankd::backupfile]
    }
    if {![info exists ::bankd::timer_running]} {
       # start new timer.
       timer [set ::bankd::intinterval] [list ::bankd::interest_timer]
       set ::bankd::timer_running 1
    }
    proc deposit {amount payee} {
        # deposit funds.
        set ::bankd::bankdb($payee) [expr [set ::bankd::bankdb($payee)] + $amount]
        ::bankd::backupdb
        return 1
    }
    proc withdraw {amount debtor} {
        # withraw bank funds.
        if {$amount <= [set ::bankd::bankdb($debtor)]} {
            # amount is less than account balance.
            set ::bankd::bankdb($debtor) [expr [set ::bankd::bankdb($debtor)] - $amount]
            ::bankd::backupdb
            return 1
        }
    }
    proc interest_timer {args} {
        # call self at timed intervals. do backup
        foreach {name value} [array get ::bankd::bankdb] {
            set interest [expr {int($value * [set ::bankd::intrate])}]
            set ::bankd::bankdb($name) [expr $value + $interest]
            if {[set ::bankd::loginterest]} {
                # log interest payment.
                putlog "Paid $name $interest in interest."
            }
        }
        ::bankd::backupdb
        timer [set ::bankd::intinterval] [list ::bankd::interest_timer]
        return 1
    }
    proc backupdb {args} {
        # backup bankdb to file.
        variable ::bankd::bankdb
        set fs [open [set ::bankd::backupfile] w+]
        puts $fs "variable ::bankd::bankdb"
        puts $fs "array set bankdb [list [array get bankdb]]"
        close $fs;
    }
    proc account {args} {
        # add/remove/edit accounts.
        set textarr [split $args]
        set action [string tolower [lindex $textarr 0]]
        set name [string tolower [lindex $textarr 1]]
        set amount [lindex $textarr 2]
        switch $action {
            "add" {
                set ::bankd::bankdb($name) 100
                ::bankd::backupdb
            }
            "remove" {
                unset ::bankd::bankdb($name)
                ::bankd::backupdb
            }
            "edit" {
                set ::bankd::bankdb($name) $amount
                ::bankd::backupdb
            }
        }
    }
    proc pub_handler {nick userhost handle channel text} {
        if {[channel get $channel bankd]} {
            set textarr [split $text]
            set first [string tolower [lindex $textarr 0]]
            set nick [string tolower $nick]
            switch $first {
                "" {
                    putserv "PRIVMSG $channel :usage: [set ::bankd::trigger] ?balance|transfer? ?args?"
                }
                "balance" {
                    if {[info exists ::bankd::bankdb($nick)]} {
                        putserv "PRIVMSG $channel :$nick, your balance is:\
                        [set ::bankd::bankdb($nick)]"
                    } else {
                        putserv "PRIVMSG $channel :$nick, you do not have an account."
                    }
                }
                "transfer" {
                    set payee [lindex $textarr 3]
                    set amount [lindex $textarr 2]
                    if {$amount == ""} {
                        putserv "PRIVMSG $channel :usage: .bank transfer <amount> <payee>"
                    } elseif {[info exists ::bankd::bankdb($nick)]} {
                         
                        if {[info exists ::bankd::bankdb($payee)]} {
                            if {[string is integer $amount]} {
                                if {[::bankd::withdraw $amount $nick] == 1} {
                                    if {[::bankd::deposit $amount $payee] == 1} {
                                        putserv "PRIVMSG $channel :transfer successful"
                                    } else {
                                        putserv "PRIVMSG $channel :cannot deposit funds."
                                    }
                                } else {
                                    putserv "PRIVMSG $channel :insufficient funds."
                                }
                            } else {
                                putserv "PRIVMSG $channel :cannot use '$amount' as an amount."
                            }
                        } else {
                            putserv "PRIVMSG $channel :$payee does not have an account."
                        }
                    } else {
                        putserv "PRIVMSG $channel :$nick, you do not have an account."
                    }
                }
            }
        }
    }
    proc dcc_admin {handle idx text} {
        set textarr [split $text]
        set text [string tolower [lindex $textarr 0]]
        set name [string tolower [lindex $textarr 1]]
        switch $text {
            "" {
                putdcc $idx "usage: .bankd ?add|remove|check|list|edit? ?args?"
            }
            "list" {
                foreach {name value} [array get ::bankd::bankdb] {
                    putdcc $idx "$name has $value coins."
                }
            }
            "add" {
                if {$name == ""} {
                    putdcc $idx "usage: .bankd add <name>"
                } elseif {![info exists ::bankd::bankdb($name)]} {
                    ::bankd::account add $name
                    putdcc $idx "account created."
                } else {
                    putdcc $idx "account already exists. Nothing to create."
                }
            }
            "check" {
                if {$name == ""} {
                    putdcc $idx "usage: .bankd check <name>"
                } elseif {[info exists ::bankd::bankdb($name)]} {
                    putdcc $idx "balance check: $name has [set ::bankd::bankdb($name)] coins."
                } else {
                    putdcc $idx "$name doesn't have an account to check."
                }
            }
            "remove" {
                if {$name == ""} {
                    putdcc $idx "usage: .bankd remove <name>"
                } elseif {[info exists ::bankd::bankdb($name)]} {
                    ::bankd::account remove $name
                    putdcc $idx "account removed."
                } else {
                    putdcc $idx "account doesn't exist. nothing to remove."
                }
            }
            "edit" {
                set amount [lindex $textarr 2]
                if {$name == ""} {
                    putdcc $idx "usage: .bankd edit <name> <amount>"
                } elseif {[info exists ::bankd::bankdb($name)]} {
                    if {[string is integer $amount]} {
                        ::bankd::account edit $name $amount
                        putdcc $idx "account edited."
                    } else {
                        putdcc $idx "cannot use '$amount' for an amount."
                    }
                } else {
                    putdcc $idx "account doesn't exist."
                }
            }
        }
    }
}
putlog "Bankd [set ::bankd::ver] Loaded"
