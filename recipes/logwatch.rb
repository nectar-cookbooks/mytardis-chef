#
# Cookbook Name:: mytardis
# Recipe:: logwatch
#
# Copyright (c) 2014, The University of Queensland
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * Neither the name of the The University of Queensland nor the
#       names of its contributors may be used to endorse or promote products
#       derived from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE UNIVERSITY OF QUEENSLAND BE LIABLE FOR
# ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#
# Add logwatch config files for MyTardis, if logwatch is installed.
#
if File.exists?("/etc/logwatch") then
  cookbook_file "/etc/logwatch/scripts/services/mytardis" do
    source "logwatch-mytardis-script"
    mode 0755
  end

  directory "/etc/logwatch/scripts/shared" do
    mode 0755
  end  
  
  cookbook_file "/etc/logwatch/scripts/shared/applymytardisdate" do
    source "logwatch-mytardis-applymytardisdate"
    mode 0755
  end
  
  cookbook_file "/etc/logwatch/conf/services/mytardis.conf" do
    source "logwatch-mytardis-service"
  end
  
  cookbook_file "/etc/logwatch/conf/logfiles/mytardis.conf" do
    source "logwatch-mytardis-logfile"
  end
end