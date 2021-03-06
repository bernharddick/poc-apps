#!/usr/bin/tclsh
##
## maze game
##	(c) BeF <bef@erlangen.ccc.de>
##

###############################################################################



package require festtcl
package require agi

agi::init
agi::answer


##
if {[catch {
##

###############################################################################

source [file join [file dirname $::argv0] mazeconfig.tcl]
source [file join [file dirname $::argv0] mazegen.tcl]
source [file join [file dirname $::argv0] mazecode.tcl]
if {$use_highscore} {
	source [file join [file dirname $::argv0] mazesql.tcl]
}

## accept language code as first parameter: de/en
if {[llength $::argv] > 0} {
	set language [lindex $::argv 0]
}

## asterisk < 1.2
#agi::exec SetLanguage $language
## asterisk >= 1.2
#agi::exec Set "LANGUAGE()=$language"
## asterisk >= 1.6.x
agi::exec Set CHANNEL(language)=$language

###############################################################################
source [file join [file dirname $::argv0] mazesound.tcl]

###############################################################################
## init vars
set cid $agi::env(agi_callerid)
set running 1
set input ""
set outfiles {}
set level 0
array set pos {x 0 y 0 z 0 dir EAST}
set DIRS {NORTH EAST SOUTH WEST}
set starttime 0
set endtime 0

## no cid error
if {$cid == ""} {
	agi::verbose "no cid" 4
	agi::hangup
}

###############################################################################
## functions ##

## stream soundfile(s) until * is pressed
proc stream {soundfile_list} {
	foreach f $soundfile_list {
		set digit [agi::streamfile $f "*"]
		if {$digit == "*"} { break }
	}
}

## stream soundfile(s) until $digits digits are pressed
proc get_data {soundfile_list wait digits} {
	set first [lrange $soundfile_list 0 [expr {[llength $soundfile_list]-2}]]
	set last [lindex $soundfile_list end]
	set input ""
	set firstwait $wait
	if {$digits == 1} { set firstwait 1000 }
	foreach f $first {
		set input [agi::getdata $f $firstwait $digits]
		if {$input != ""} { break }
	}
	if {$input == ""} {
		set input [agi::getdata $last $wait $digits]
	}
	return $input
}

## return a random element from the list l
proc random_choice {l} {
	expr {srand([clock clicks])}
	return [lindex $l [expr {int(rand()*[llength $l])}]]
}


###############################################################################

## intro
stream [random_choice $sounds(intro)]

## game loop
while { 1 } {
	gen_maze $level $cid
	foreach line [show_level 0] { agi::verbose "$cid $line" 3 }
	
	stream [random_choice $sounds(level_intro)]
	agi::saynumber $level
	
	set running 1
	set pos(x) 0
	set pos(y) [regsub {0,(\d+),0} $::sz(start) {\1}]
	set pos(z) 0
	set pos(dir) EAST
	set starttime [clock seconds]
	set endtime $starttime

	while {$running} {
		set m $::maze($pos(x),$pos(y),$pos(z))
		set dir_left [lindex $DIRS [expr {([lsearch $DIRS $pos(dir)] - 1 )%4}]]
		set dir_right [lindex $DIRS [expr {([lsearch $DIRS $pos(dir)] + 1 )%4}]]
		set dir_behind [lindex $DIRS [expr {([lsearch $DIRS $pos(dir)] + 2 )%4}]]

		set input ""
		if {$outfiles != {}} {
			set input [get_data $outfiles 10000 1]
		}
		set outfiles {}
		agi::verbose "CID $cid, LEVEL $level POS $pos(x)x$pos(y)x$pos(z)" 4
		switch $input {
			4 {
				## turn left
				set pos(dir) $dir_left
			}
			6 {
				## turn right
				set pos(dir) $dir_right
			}
			2 {
				## go upstairs
				if {$m & $::DOOR(UP)} {
					set newpos [MOVETO $pos(x) $pos(y) $pos(z) $DIR(UP)]
					set pos(x) [lindex $newpos 0]
					set pos(y) [lindex $newpos 1]
					set pos(z) [lindex $newpos 2]
				} else {
					set outfiles [random_choice $sounds(stair_error_UP)]
				}
			}
			8 {
				## go downstairs
				if {$m & $::DOOR(DOWN)} {
					set newpos [MOVETO $pos(x) $pos(y) $pos(z) $DIR(DOWN)]
					set pos(x) [lindex $newpos 0]
					set pos(y) [lindex $newpos 1]
					set pos(z) [lindex $newpos 2]
				} else {
					set outfiles [random_choice $sounds(stair_error_DOWN)]
				}
			}
			5 {
				## go ahead
				if {$m & $::WALL($pos(dir))} {
					set outfiles [random_choice $sounds(wall_error)]
				} else {
					set newpos [MOVETO $pos(x) $pos(y) $pos(z) $DIR($pos(dir))]
					set pos(x) [lindex $newpos 0]
					set pos(y) [lindex $newpos 1]
					set pos(z) [lindex $newpos 2]
				}
			}
			0 {
				## enter level code / change level
				set inlevel [agi::getdata [random_choice $sounds(enter_level_nr)] 10000 2]
				set incode [agi::getdata [random_choice $sounds(enter_level_code)] 10000 4]
				regsub {^0} $inlevel {} inlevel
				regsub -all {[^\d]} $inlevel {} inlevel
				if {![string is integer "$inlevel"]} { set inlevel 0 }
				if {$inlevel == ""} { set inlevel 0 }
				if {$incode != [code $inlevel $cid]} {
					stream [random_choice $sounds(level_code_incorrect)]
				} else {
					set level $inlevel
					break
				}
			}
			9 {
				## announce level code
				set snd [random_choice $sounds(level_code)]
				stream [lindex $snd 0]
				agi::saynumber $level
				stream [lindex $snd 1]
				agi::saydigits [code $level $cid]
			}
			1 {
				## help
				stream [random_choice $sounds(help)]
			}
			#3 {
				## bible
			#	agi::streamfile {/home/bef/sounds/Genesis_01}
			#}
			{*} {
				## compass
				set outfiles [random_choice $sounds(compass_$pos(dir))]
			}
			default {
				## impression

				set corridors 0
				foreach side [list $::WALL($dir_left) $::WALL($dir_right) $::WALL($pos(dir)) $::WALL($dir_behind) $::WALL(UP) $::WALL(DOWN)] {
					if {[expr {!($m & $side)}]} { incr corridors }
				}
				if {$corridors > 2} {
					set outfiles [random_choice $sounds(imp_intersect)]
				} else {
					if {$m & $::WALL($pos(dir))} {
						set outfiles [random_choice $sounds(imp_wall)]
					} else {
						set outfiles [random_choice $sounds(imp_free)]
					}
				}
			}
		}

		if {$pos(x) == -1} {
			## exit through entrance
			set running 0
			stream [random_choice $sounds(exit_entrance)]
		}
		if {$pos(x) == $::sz(x)} {
			## exit through exit
			set running 0
			stream [random_choice $sounds(level_succeeded)]

			set endtime [clock seconds]
			## log to highscore
			if {$use_highscore} {
				if {[catch {
					::mazedb::connect_db
					::mazedb::add_to_highscore $cid $level $starttime $endtime
					::mazedb::disconnect_db
				} eid]} {
					agi::verbose "db error: $eid" 3
				}
			}

			## switch to next level
			incr level

			## announce level code
			set snd [random_choice $sounds(level_code)]
			stream [lindex $snd 0]
			agi::saynumber $level
			stream [lindex $snd 1]
			agi::saydigits [code $level $cid]

		}
	}

	if {$level > $::maxlevel} {
		## winner
		set level $::maxlevel
		stream [random_choice $sounds(game_over)]
		agi::exec echo ""
		break
	}
	
}

##
} fid]} {
	agi::verbose "error $fid" 4
}
##
