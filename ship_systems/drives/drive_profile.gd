class_name DriveProfile
extends Resource
## What a kind of engine gives off with thrust (sensor model, fog of war): per
## meganewton of thrust, added to the ship's base output each tick. Chemical
## drives (most factions, Earth Alliance and Narn too) give off EM, gravitic
## drives (Centauri, Minbari) a gravimetric signature, and esoteric drives
## (Shadows, Vorlons) neutrinos. Signatures are signal 1.0 at 1 km, falling off
## with the square of the distance (see Sensor).

@export var name := ""
@export var em_per_meganewton := 0.0
@export var gravimetric_per_meganewton := 0.0
@export var neutrino_per_meganewton := 0.0
