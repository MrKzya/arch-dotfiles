
set -gx EDITOR nano

# overwrite greeting
# potentially disabling fastfetch
#function fish_greeting
#    # smth smth
#end
starship init fish | source
set -g fish_greeting ""
fastfetch
function fish_user_key_bindings 
	bind \cl 'clear; commandline -f repaint'
end
