#!/usr/bin/env ruby 
# encoding: utf-8

$: << File.join(File.dirname(__FILE__), '.')
                  
require 'pathname'
require 'zip/zipfilesystem'
require 'iservice' 
require 'iafctools'
require 'inotify' 

unless ARGV.size == 2
  puts "Usage:   #{$0} 	action params"
	puts "Example:      	i 'ipa/ARCHIVE.ipa'"
	puts "					 			u 'com.evolonix.Linux-Reference-Guide'"
  exit
end 

p ARGV

class IpaInstallService < DeviceService 
	def install(ipa_path)
		@is_work = true   
		# ipainstall.rb i libimobiledevice/tools/ipa/ARCHIVE.ipa  
		# /ipa/ARCHIVE.ipa/Payload/Linux Reference Guide.app/SC_Info/Linux Reference Guide.sinf
		app_sinf = ""
		# /ipa/ARCHIVE.ipa/iTunesMetadata.plist
		meta_data = ""
		Zip::ZipFile.open(ipa_path) {|zipfile| 
			Zip::ZipFile.foreach(ipa_path) do | entry |
				# p entry
				if entry.to_s == "iTunesMetadata.plist"
					meta_data = zipfile.read(entry) 
					meta_data.blob = true
				elsif entry.to_s =~ /Payload\/.+app\/SC_Info\/.+sinf/
					app_sinf = zipfile.read(entry)
					app_sinf.blob = true 
				end
			end
		}
		                                                                    
		obj = {"ClientOptions"=>{"ApplicationSINF" => app_sinf, "iTunesMetadata" => meta_data},
			"Command" => "Install",
			"PackagePath" => File.join("PublicStaging", Pathname.new(ipa_path).basename)
		}
		pp obj
		write_plist(@socket, obj)
    
  end
  def uninstall(app_id) 
		@is_work = true                                       
		# ipainstall.rb u "com.evolonix.Linux-Reference-Guide"
		# CFBundleIdentifier = "com.evolonix.Linux-Reference-Guide"
		obj ={"Command" => "Uninstall", "ApplicationIdentifier" => app_id}
		pp obj
		write_plist(@socket, obj) 
		
  end
    
	def update(t_event)
		p "UPDATE"
		@is_work = false 
	end
	
	def wait         
		# {"Status"=>"TakingInstallLock", "PercentComplete"=>0} 
		# {"Status"=>"Complete"}
		# {"Error"=>"APIInternalError"}
		while @is_work do
			obj = read_plist(@socket)
			# pp obj
			if obj.include?("Error")
				p "ERROR" 
				break
			else obj.include?("Status")
				case obj["Status"]
				when "Complete"
					p "COMPLETE" 
					break
				else   
					p "#{obj["Status"]} == #{obj["PercentComplete"]}% == " 
				end
			end  
	 	end
	end
end

if __FILE__ == $0
  l = DeviceRelay.new
  
  l.query_type
  
  pub_key = l.get_value("DevicePublicKey")
  p "pub_key:", pub_key
  #
  l.pair_device(pub_key)
  
  # l.validate_pair(pub_key)
  
  @session_id = l.start_session
  p "session_id:", @session_id
  
  # ssl_enable
  @notify_port = l.start_service(AMSVC_NOTIFICATION_PROXY) 
	@afc_port = l.start_service(AMSVC_AFC)
	@install_port = l.start_service(AMSVC_INSTALLATION_PROXY)
  # 
  l.stop_session(@session_id)
  # notify
	if @afc_port
	  port = @afc_port>>8 | (@afc_port & 0xff)<<8
    @afc = AFCService.new(port)
 	end
	if @install_port
		port = @install_port>>8 | (@install_port & 0xff)<<8
    @inst = IpaInstallService.new(port)
  end
	if @notify_port
		port = @notify_port>>8 | (@notify_port & 0xff)<<8
		@notify = INotifyService.new(port) 
		@notify.add_observer(@inst)
	end
	if @notify
		case ARGV[0]
		when "install", "i"
			ipa_path = ARGV[1]                  
			
			if @afc_port
				
				# afc
	      p "Copying 'Linux 1.2.ipa' --> 'PublicStaging/Linux 1.2.ipa'" 
				fpath = File.join("PublicStaging", Pathname.new(ipa_path).basename)
				h = @afc.open(fpath, 3) 
				io = File.open(ipa_path)
				while chunk = io.read(8192-48)
					@afc.write(h, chunk)
				end
		    @afc.close(h)
		 	end
			if @inst
				# install
		    @notify.observe("com.apple.mobile.application_installed")

				@inst.install(ipa_path) 

				@inst.wait     
			end
		else 
			# uninstall 
			if @inst                    
				@notify.observe("com.apple.mobile.application_uninstalled")
				
				@inst.uninstall(ARGV[1])  
				
				@inst.wait  
			end
		end
	end     
end  

__END__
                                                       

<key>Request</key>\n\t<string>StartService</string>\n\t<key>Service</key>\n\t<string>com.apple.mobile.notification_proxy</string>\n</d
<key>Port</key>\n\t<integer>49320</integer>\n\t<key>Request</key>\n\t<string>StartService</string>\n\t<key>Result</key>\n\t<string>Success</string>\n\t<key>Service</key>\n\t<string>com.apple.mobile.notification_proxy</string>\n</dict>\n</plist>\n"
<key>MessageType</key>\n\t<string>Connect</string>\n\t<key>DeviceID</key>\n\t<integer>35</integer>\n\t<key>PortNumber</key>\n\t<integer>43200</integer>\n\t<key>ProgName</key>\n\t<string>libusbmuxd</string>\n</dict>\n</plist>\n"
<key>Command</key>\n\t<string>ObserveNotification</string>\n\t<key>Name</key>\n\t<string>com.apple.mobile.application_installed</string>\n</dict>\n</plist>\n"
<key>Command</key>\n\t<string>ObserveNotification</string>\n\t<key>Name</key>\n\t<string>com.apple.mobile.application_uninstalled</string>\n</dict>\n</plist>\n"

<key>Request</key>\n\t<string>StartService</string>\n\t<key>Service</key>\n\t<string>com.apple.mobile.installation_proxy</string>\n</dict>\n</plist>\n"
<key>Port</key>\n\t<integer>49322</integer>\n\t<key>Request</key>\n\t<string>StartService</string>\n\t<key>Result</key>\n\t<string>Success</string>\n\t<key>Service</key>\n\t<string>com.apple.mobile.installation_proxy</string>\n</dict>\n</plist>\n"
<key>MessageType</key>\n\t<string>Connect</string>\n\t<key>DeviceID</key>\n\t<integer>35</integer>\n\t<key>PortNumber</key>\n\t<integer>43712</integer>\n\t<key>ProgName</key>\n\t<string>libusbmuxd</string>\n</dict>\n</plist>\n"

<key>Request</key>\n\t<string>StartService</string>\n\t<key>Service</key>\n\t<string>com.apple.afc</string>\n</dict>\n</plist>\n"
<key>Port</key>\n\t<integer>49324</integer>\n\t<key>Request</key>\n\t<string>StartService</string>\n\t<key>Result</key>\n\t<string>Success</string>\n\t<key>Service</key>\n\t<string>com.apple.afc</string>\n</dict>\n</plist>\n"

<key>Request</key>\n\t<string>StopSession</string>\n\t<key>SessionID</key>\n\t<string>8143E5E1-FEDE-4148-8BA3-E48B597EF9DE</string>\n</dict>\n</plist>\n"

<key>MessageType</key>\n\t<string>Connect</string>\n\t<key>DeviceID</key>\n\t<integer>35</integer>\n\t<key>PortNumber</key>\n\t<integer>44224</integer>\n\t<key>ProgName</key>\n\t<string>libusbmuxd</string>\n</dict>\n</plist>\n"
Copying 'Linux 1.2.ipa' --> 'PublicStaging/Linux 1.2.ipa'
done.
Installing 'PublicStaging/Linux 1.2.ipa'

<key>ClientOptions</key>\n\t<dict>\n\t\t
<key>ApplicationSINF</key>
<data>\n\t\tAAAECHNpbmYAAAAMZnJtYWdhbWUAAAAUc2NobQAAAABpdHVuAAAAAAAAA1hzY2hpAAAA\n\t\tDHVzZXIQhiFMAAAADGtleSAAAAACAAAAGGl2aXYYnv9WTKrEM+5mms9n1eKhAAAAWHJp\n\t\tZ2h2ZUlEAAOucHBsYXQAAAAFYXZlcgEBAQB0cmFuySalcHNvbmcW29kPdG9vbFA0MTlt\n\t\tZWRpAAAAgG1vZGU", 'A' <repeats 30 times>, "QhuYW1lRFVBTiBMSQAAAAAA\n\t\t", 'A' <repeats 68 times>, "\n\t\t", 'A' <repeats 68 times>, "\n\t\t", 'A' <repeats 68 times>, "\n\t\t", 'A' <repeats 68 times>, "\n\t\t", 'A' <repeats 57 times>, "cBwcml24fQn\n\t\tZL6KnkFPL6Az3VHdCCNpQEE8imNWPRltEOEeW5hzz3Wgz9sxKo+AyCFXrl0zddG2eNYw\n\t\t+blLdIS6/mTNm3W77fOiqPlO/3duC2FqJqlsQE5emWXUuNhD66Ah5jaz3Wjjnx4J4jEk\n\t\teqQfK5QOu96k0pdjFSCtRtxA4Y9rS8IHhHpUrAAgJJmI9Rksv5zALK/ow9HBlYmzkLkw\n\t\tkuCbEXmPTlSfsSmzfDB4IjFSWFNwgA7NBhskD+xydBd9B2MWCtl+LXj9KlWMpn7iU4E9\n\t\t/slxeZRYLx0TY2sj/nl9bfwiv83sSJJ9d+rPGKyZCLM01EdwPudAt71gG++1hjrbReaF\n\t\tNOm88uQSX83ff7fBiiYqWOvGmJBcxN9Cpsm9zhjC40UobO+1/tHy23C8s8UzWu4arMig\n\t\tZpGk9LgAIFCy+4FnMhIus2t/XxuvUBykFe8SOa58sSVFT7IhZvpSGjzOoEGG/ZS/hQyF\n\t\tDapTGAWt2YZYfxhiLOoJrXGNp26EteRfgFZXwxmb8gl7FoGLc4VsPuVosMPeHcg2TzcN\n\t\tmo7nTXw+JAl2/HcZKUD4ZATp4jpX", 'A' <repeats 14 times>, "CIc2lnbohln0ejyCgUWah/sMjR\n\t\typVfrUvTH5MAkdH3zfgJ6Mv57geEtjIOgkS5Ib1EGp0oFnZhGR7xzE2qJIifyQ9Fblph\n\t\tqgs38Oam0zZo11dFvi6sCNkkBq46RCXtkunjVTOUyRCPDJVjawVcv4ukh6/O5kaHuWQO\n\t\tyQ2yvmfYhdHputp6\n\t\t</data>
<key>iTunesMetadata</key>\n\t\t<data>\n\t\tYnBsaXN0MDDfEB0BAgMEBQYHCAkKCwwNDg8QERITFBUWFxgZGhscHR4fIyQlJicoKSor\n\t\tLC0uLypETD4+TU5PUFFSUlNVWWNvcHlyaWdodF8QInNvZnR3YXJlVmVyc2lvbkV4dGVy\n\t\tbmFsSWRlbnRpZmllcnNVZ2VucmVUa2luZFhidXktb25seV8QFHNvZnR3YXJlSWNvbjU3\n\t\teDU3VVJMUXNWaXRlbUlkXxAWc29mdHdhcmVJY29uTmVlZHNTaGluZVxwbGF5bGlzdE5h\n\t\tbWVfEBdzb2Z0d2FyZVZlcnNpb25CdW5kbGVJZF8QIXNvZnR3YXJlVmVyc2lvbkV4dGVy\n\t\tbmFsSWRlbnRpZmllcl8QE3ZlcnNpb25SZXN0cmljdGlvbnNZYnV5UGFyYW1zXxAiY29t\n\t\tLmFwcGxlLmlUdW5lc1N0b3JlLmRvd25sb2FkSW5mb1hpdGVtTmFtZVZyYXRpbmddYnVu\n\t\tZGxlVmVyc2lvbl8QEGRybVZlcnNpb25OdW1iZXJVcHJpY2VdZmlsZUV4dGVuc2lvblxw\n\t\tcmljZURpc3BsYXlXZ2VucmVJZFhhcnRpc3RJZFtyZWxlYXNlRGF0ZVphcnRpc3ROYW1l\n\t\tXxAScGxheWxpc3RBcnRpc3ROYW1lXxAac29mdHdhcmVTdXBwb3J0ZWREZXZpY2VJZHNY\n\t\tdmVuZG9ySWRvEA8AqQAgADIAMAAxADAAIABFAHYAbwBsAG8AbgBpAHijICEiEgArLpoS\n\t\tADBlphIAMN81WVJlZmVyZW5jZVhzb2Z0d2FyZQlfEEhodHRwOi8vYTEucGhvYm9zLmFw\n\t\tcGxlLmNvbS91cy9yMTAwMC8wMjEvUHVycGxlL2U5Lzg1L2FiL216aS5raXRqaG9sai5w\n\t\tbmcSAAIwURIW29kPCF8QFUxpbnV4IFJlZmVyZW5jZSBHdWlkZV8QImNvbS5ldm9sb25p\n\t\teC5MaW51eC1SZWZlcmVuY2UtR3VpZGUSADDfNRIBAQEAXxBNcHJvZHVjdFR5cGU9QyZz\n\t\tYWxhYmxlQWRhbUlkPTM4MzUwNjcwMyZwcmljaW5nUGFyYW1ldGVycz1TVERRJnByaWNl\n\t\tPTAmY3QtaWQ9MTTUMDEyMzRBQkNbYWNjb3VudEluZm9ccHVyY2hhc2VEYXRlXxASbWVk\n\t\taWFBc3NldEZpbGVuYW1lXxAUYXJ0d29ya0Fzc2V0RmlsZW5hbWXWNTY3ODk6OzwpPj9A\n\t\tXxATQ3JlZGl0RGlzcGxheVN0cmluZ18QEUFjY291bnRVUkxCYWdUeXBlXxAUQWNjb3Vu\n\t\tdFNvY2lhbEVuYWJsZWRbQWNjb3VudEtpbmRaRFNQZXJzb25JRFdBcHBsZUlEUFpwcm9k\n\t\tdWN0aW9uCBAAEhCGIUxXbGl0ZWtva18QFDIwMTAtMTItMDlUMTU6MjU6MzZaXxAcMzgz\n\t\tNTA2NzAzLTYwMDAxOTExNTI4NzcwLmlwYV8QHDM4MzUwNjcwMy02MDAwMTkxMTUyODc3\n\t\tMC5qcGfURUZHSElKSztUcmFua1VsYWJlbFZzeXN0ZW1XY29udGVudBBkUjQrXGl0dW5l\n\t\tcy1nYW1lc1MxLjJULmFwcFRGcmVlERd2EhVmw35fEBQyMDEwLTExLTE3VDAyOjA1OjQx\n\t\tWlhFdm9sb25peKFUEAESAAOucAAIAEUATwB0AHoAfwCIAJ8AoQCoAMEAzgDoAQwBIgEs\n\t\tAVEBWgFhAW8BggGIAZYBowGrAbQBwAHLAeAB/QIGAicCKwIwAjUCOgJEAk0CTgKZAp4C\n\t\towKkArwC4QLmAusDOwNEA1ADXQNyA4kDlgOsA8AD1wPjA+4D9gP3BAIEAwQFBAoEEgQp\n\t\tBEgEZwRwBHUEewSCBIoEjASPBJwEoASlBKoErQSyBMkE0gTUBNYAAAAAAAACAQAAAAAA\n\t\tAABW", 'A' <repeats 19 times>, "E2w==\n\t\t</data>
</dict>
<key>Command</key><string>Install</string>
<key>PackagePath</key><string>PublicStaging/Linux 1.2.ipa</string>
</dict>\n</plist>\n"

<key>PercentComplete</key>\n\t<integer>0</integer>\n\t<key>Status</key>\n\t<string>TakingInstallLock</string>\n</dict>\n</plist>\n"
<key>PercentComplete</key>\n\t<integer>5</integer>\n\t<key>Status</key>\n\t<string>CreatingStagingDirectory</string>\n</dict>\n</plist>\n"

Install - CreatingStagingDirectory (5%)
<key>PercentComplete</key>\n\t<integer>15</integer>\n\t<key>Status</key>\n\t<string>ExtractingPackage</string>\n</dict>\n</plist>\n"
Install - ExtractingPackage (15%)
<key>PercentComplete</key>\n\t<integer>20</integer>\n\t<key>Status</key>\n\t<string>InspectingPackage</string>\n</dict>\n</plist>\n"
Install - InspectingPackage (20%)
<key>PercentComplete</key>\n\t<integer>30</integer>\n\t<key>Status</key>\n\t<string>PreflightingApplication</string>\n</dict>\n</plist>\n"
Install - PreflightingApplication (30%)
<key>PercentComplete</key>\n\t<integer>40</integer>\n\t<key>Status</key>\n\t<string>VerifyingApplication</string>\n</dict>\n</plist>\n"
Install - VerifyingApplication (40%)
<key>PercentComplete</key>\n\t<integer>50</integer>\n\t<key>Status</key>\n\t<string>CreatingContainer</string>\n</dict>\n</plist>\n"
Install - CreatingContainer (50%)
<key>PercentComplete</key>\n\t<integer>60</integer>\n\t<key>Status</key>\n\t<string>InstallingApplication</string>\n</dict>\n</plist>\n"
Install - InstallingApplication (60%)
<key>PercentComplete</key>\n\t<integer>70</integer>\n\t<key>Status</key>\n\t<string>PostflightingApplication</string>\n</dict>\n</plist>\n"
Install - PostflightingApplication (70%)
<key>PercentComplete</key>\n\t<integer>80</integer>\n\t<key>Status</key>\n\t<string>SandboxingApplication</string>\n</dict>\n</plist>\n"
<key>PercentComplete</key>\n\t<integer>90</integer>\n\t<key>Status</key>\n\t<string>GeneratingApplicationMap</string>\n</dict>\n</plist>\n"
<key>Status</key>\n\t<string>Complete</string>\n</dict>\n</plist>\n"
Install - Complete
[Switching to process 55955 thread 0x1603]
<key>Command</key>\n\t<string>RelayNotification</string>\n\t<key>Name</key>\n\t<string>com.apple.mobile.application_installed</string>\n</dict>\n</plist>\n"
