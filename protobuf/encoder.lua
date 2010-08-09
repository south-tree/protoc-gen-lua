--
--------------------------------------------------------------------------------
--         FILE:  encoder.lua
--        USAGE:  ./encoder.lua 
--  DESCRIPTION:  
--      OPTIONS:  ---
-- REQUIREMENTS:  ---
--         BUGS:  ---
--        NOTES:  ---
--       AUTHOR:  Sean Lin (NetSnail), <netsnail@gmail.com>
--      COMPANY:  NetEase
--      VERSION:  1.0
--      CREATED:  2010年07月29日 19时30分46秒 CST
--     REVISION:  ---
--------------------------------------------------------------------------------
--
local string = string
local table = table
local ipairs = ipairs
local assert =assert

local pb = require "pb"
local wire_format = require "wire_format"
module "encoder"

function _VarintSize(value)
    if value <= 0x7f then return 1 end
    if value <= 0x3fff then return 2 end
    if value <= 0x1fffff then return 3 end
    if value <= 0xfffffff then return 4 end
    return 5 
end

function _SignedVarintSize(value)
    if value < 0 then return 10 end
    if value <= 0x7f then return 1 end
    if value <= 0x3fff then return 2 end
    if value <= 0x1fffff then return 3 end
    if value <= 0xfffffff then return 4 end
    return 5
end

function _TagSize(field_number)
  return _VarintSize(wire_format.PackTag(field_number, 0))
end

function _SimpleSizer(compute_value_size)
    return function(field_number, is_repeated, is_packed)
        local tag_size = _TagSize(field_number)
        if is_packed then
            local VarintSize = _VarintSize
            return function(value)
                result = 0
                for element in value do
                    result = result + compute_value_size(element)
                end
                return result + VarintSize(result) + tag_size
            end
        elseif is_repeated then
            return function(value)
                result = tag_size * len(value)
                for element in value do
                    result = result + compute_value_size(element)
                end
                return result
            end
        else
            return function (value)
                return tag_size + compute_value_size(value)
            end
        end
    end
end

function _ModifiedSizer(compute_value_size, modify_value)
    return function (field_number, is_repeated, is_packed)
        local tag_size = _TagSize(field_number)
        if is_packed then
            local VarintSize = _VarintSize
            return function (value)
                result = 0
                for element in value do
                    result = result + compute_value_size(modify_value(element))
                end
                return result + VarintSize(result) + tag_size
            end
        elseif is_repeated then
            return function (value)
                result = tag_size * len(value)
                for element in value do
                    result = result + compute_value_size(modify_value(element))
                end
                return result
            end
        else
            return function (value)
                return tag_size + compute_value_size(modify_value(value))
            end
        end
    end
end

function _FixedSizer(value_size)
    return function (field_number, is_repeated, is_packed)
        local tag_size = _TagSize(field_number)
        if is_packed then
            local VarintSize = _VarintSize
            return function (value)
                local result = len(value) * value_size
                return result + VarintSize(result) + tag_size
            end
        elseif is_repeated then
            local element_size = value_size + tag_size
            return function(value)
                return len(value) * element_size
            end
        else
            field_size = value_size + tag_size
            return function (value)
                return field_size
            end
        end
    end
end

Int32Sizer = _SimpleSizer(_SignedVarintSize)
Int64Sizer = Int32Sizer
EnumSizer = Int32Sizer

UInt32Sizer = _SimpleSizer(_VarintSize)
UInt64Sizer = UInt32Sizer 

SInt32Sizer = _ModifiedSizer(_SignedVarintSize, wire_format.ZigZagEncode)
SInt64Sizer = SInt32Sizer

Fixed32Sizer = _FixedSizer(4) 
SFixed32Sizer = Fixed32Sizer
FloatSizer = Fixed32Sizer

Fixed64Sizer = _FixedSizer(8) 
SFixed64Sizer = Fixed32Sizer
DoubleSizer = Fixed32Sizer

BoolSizer = _FixedSizer(1)


function StringSizer(field_number, is_repeated, is_packed)
    local tag_size = _TagSize(field_number)
    local VarintSize = _VarintSize
    assert(not is_packed)
    if is_repeated then
        return function(value)
            local result = tag_size * #value
            for _, element in ipairs(value) do
                local l = #element
                result = result + VarintSize(l) + l
            end
            return result
        end
    else
        return function(value)
            local l = #value
            return tag_size + VarintSize(l) + l
        end
    end
end

function BytesSizer(field_number, is_repeated, is_packed)
    local tag_size = _TagSize(field_number)
    local VarintSize = _VarintSize
    assert(not is_packed)
    if is_repeated then
        return function (value)
            local result = tag_size * #value
            for element in value do
                local l = #element
                result = result + VarintSize(l) + l
            end
            return result
        end
    else
        return function (value)
            local l = #value
            return tag_size + VarintSize(l) + l
        end
    end
end

function MessageSizer(field_number, is_repeated, is_packed)
    local tag_size = _TagSize(field_number)
    local VarintSize = _VarintSize
    assert(not is_packed)
    if is_repeated then
        return function(value)
            local result = tag_size * #value
            for element in value do
                local l = element.ByteSize()
                result = result + VarintSize(l) + l
            end
            return result
        end
    else
        return function (value)
            local l = value.ByteSize()
            return tag_size + VarintSize(l) + l
        end
    end
end


-- ====================================================================
--  Encoders!

local _EncodeVarint = pb.varint_encoder
local _EncodeSignedVarint = pb.signed_varint_encoder


function _VarintBytes(value)
    local buff = {}
    local write = function(value)
        buff[#buff + 1] = value 
    end
    _EncodeSignedVarint(write, value)
    return table.concat(buff)
end

function TagBytes(field_number, wire_type)
  return _VarintBytes(wire_format.PackTag(field_number, wire_type))
end

function _SimpleEncoder(wire_type, encode_value, compute_value_size)
    return function(field_number, is_repeated, is_packed)
        if is_packed then
            local tag_bytes = TagBytes(field_number, wire_format.WIRETYPE_LENGTH_DELIMITED)
            local EncodeVarint = _EncodeVarint
            return function(write, value)
                write(tag_bytes)
                local size = 0
                for _, element in ipairs(value) do
                    size = size + compute_value_size(element)
                end
                EncodeVarint(write, size)
                for element in value do
                    encode_value(write, element)
                end
            end
        elseif is_repeated then
            local tag_bytes = TagBytes(field_number, wire_type)
            return function(write, value)
                for _, element in ipairs(value) do
                    write(tag_bytes)
                    encode_value(write, element)
                end
            end
        else
            local tag_bytes = TagBytes(field_number, wire_type)
            return function(write, value)
                write(tag_bytes)
                return encode_value(write, value)
            end
        end
    end
end

function _ModifiedEncoder(wire_type, encode_value, compute_value_size, modify_value)
    return function (field_number, is_repeated, is_packed)
        if is_packed then
            local tag_bytes = TagBytes(field_number, wire_format.WIRETYPE_LENGTH_DELIMITED)
            local EncodeVarint = _EncodeVarint
            return function (write, value)
                write(tag_bytes)
                local size = 0
                for _, element in ipairs(value) do
                    size = size + compute_value_size(modify_value(element))
                end
                EncodeVarint(write, size)
                for _, element in ipairs(value) do
                    encode_value(write, modify_value(element))
                end
            end
        elseif is_repeated then
            local tag_bytes = TagBytes(field_number, wire_type)
            return function (write, value)
                for _, element in ipairs(value) do
                    write(tag_bytes)
                    encode_value(write, modify_value(element))
                end
            end
        else
            local tag_bytes = TagBytes(field_number, wire_type)
            return function (write, value)
                write(tag_bytes)
                return encode_value(write, modify_value(value))
            end
        end
    end
end

function _StructPackEncoder(wire_type, value_size, format)
    return function(field_number, is_repeated, is_packed)
        local struct_pack = pb.struct_pack
        if is_packed then
            local tag_bytes = TagBytes(field_number, wire_format.WIRETYPE_LENGTH_DELIMITED)
            local EncodeVarint = _EncodeVarint
            return function (write, value)
                write(tag_bytes)
                EncodeVarint(write, #value * value_size)
                for _, element in ipairs(value) do
                    write(struct_pack(format, element))
                end
            end
        elseif is_repeated then
            local tag_bytes = TagBytes(field_number, wire_type)
            return function (write, value)
                for _, element in ipairs(value) do
                    write(tag_bytes)
                    write(struct_pack(format, element))
                end
            end
        else
            local tag_bytes = TagBytes(field_number, wire_type)
            return function (write, value)
                write(tag_bytes)
                return write(struct_pack(format, value))
            end
        end

    end
end

Int32Encoder = _SimpleEncoder(wire_format.WIRETYPE_VARINT, _EncodeSignedVarint, _SignedVarintSize)
Int64Encoder = Int32Encoder
EnumEncoder = Int32Encoder

UInt32Encoder = _SimpleEncoder(wire_format.WIRETYPE_VARINT, _EncodeVarint, _VarintSize)
UInt64Encoder = UInt32Encoder

SInt32Encoder = _ModifiedEncoder(
    wire_format.WIRETYPE_VARINT, _EncodeVarint, _VarintSize,
    wire_format.ZigZagEncode)

SInt64Encoder = SInt32Encoder

Fixed32Encoder  = _StructPackEncoder(wire_format.WIRETYPE_FIXED32, 32, string.byte('I'))
Fixed64Encoder  = _StructPackEncoder(wire_format.WIRETYPE_FIXED64, 64, string.byte('Q'))
SFixed32Encoder = _StructPackEncoder(wire_format.WIRETYPE_FIXED32, 32, string.byte('i'))
SFixed64Encoder = _StructPackEncoder(wire_format.WIRETYPE_FIXED64, 64, string.byte('q'))
FloatEncoder    = _StructPackEncoder(wire_format.WIRETYPE_FIXED32, 32, string.byte('f'))
DoubleEncoder   = _StructPackEncoder(wire_format.WIRETYPE_FIXED64, 64, string.byte('d'))


function BoolEncoder(field_number, is_repeated, is_packed)
    local false_byte = '\0'
    local true_byte = '\1'
    if is_packed then
        local tag_bytes = TagBytes(field_number, wire_format.WIRETYPE_LENGTH_DELIMITED)
        local EncodeVarint = _EncodeVarint
        return function (write, value)
            write(tag_bytes)
            EncodeVarint(write, #value)
            for _, element in ipairs(value) do
                if element then
                    write(true_byte)
                else
                    write(false_byte)
                end
            end
        end
    elseif is_repeated then
        local tag_bytes = TagBytes(field_number, wire_format.WIRETYPE_VARINT)
        return function(write, value)
            for _, element in ipairs(value) do
                write(tag_bytes)
                if element then
                    write(true_byte)
                else
                    write(false_byte)
                end
            end
        end
    else
        local tag_bytes = TagBytes(field_number, wire_format.WIRETYPE_VARINT)
        return function (write, value)
            write(tag_bytes)
            if value then
                return write(true_byte)
            end
            return write(false_byte)
        end
    end
end

function StringEncoder(field_number, is_repeated, is_packed)
    local tag = TagBytes(field_number, wire_format.WIRETYPE_LENGTH_DELIMITED)
    local EncodeVarint = _EncodeVarint
    assert(not is_packed)
    if is_repeated then
        return function (write, value)
            for element in value do
--                encoded = element.encode('utf-8')
                write(tag)
                EncodeVarint(write, #value)
                write(element)
            end
        end
    else
        return function (write, value)
--            local encoded = value.encode('utf-8')
            write(tag)
            EncodeVarint(write, #value)
            return write(value)
        end
    end
end

function BytesEncoder(field_number, is_repeated, is_packed)
    local tag = TagBytes(field_number, wire_format.WIRETYPE_LENGTH_DELIMITED)
    local EncodeVarint = _EncodeVarint
    assert(not is_packed)
    if is_repeated then
        return function (write, value)
            for _, element in ipairs(value) do
                write(tag)
                EncodeVarint(write, #element)
                write(element)
            end
        end
    else
        return function(write, value)
            write(tag)
            EncodeVarint(write, #value)
            return write(value)
        end
    end
end


function MessageEncoder(field_number, is_repeated, is_packed)
    local tag = TagBytes(field_number, wire_format.WIRETYPE_LENGTH_DELIMITED)
    local EncodeVarint = _EncodeVarint
    assert(not is_packed)
    if is_repeated then
        return function(write, value)
            for _, element in ipairs(value) do
                write(tag)
                EncodeVarint(write, element:ByteSize())
                element:_InternalSerialize(write)
            end
        end
    else
        return function (write, value)
            write(tag)
            EncodeVarint(write, value:ByteSize())
            return value:_InternalSerialize(write)
        end
    end
end

