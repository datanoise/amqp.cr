#!/bin/sh

cd codegen
crystal gen.cr > ../amqp/spec091.cr
