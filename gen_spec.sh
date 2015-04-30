#!/bin/sh

cd codegen
crystal gen.cr > ../src/amqp/spec091.cr
