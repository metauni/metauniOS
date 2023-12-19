local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rose = require(ReplicatedStorage.Packages.Rose)

local export = {}

export type Schema = any

export type Serialised = {
	__schema: Schema,
	__data: any
}




return export