../PandA-bambu/bambu.AppImage --generate-interface=INFER mmult_accel.cpp --top-fname=mmult_accel
 ==  Bambu executed with: /tmp/.mount_bambu.hm7Z7N/usr/bin/bambu --generate-interface=INFER --top-fname=mmult_accel mmult_accel.cpp

# We check the return code
  echo $?

# We have to copy some memories that were not created by bambu:
cp array_ref_428617.mem array.mem
cp array_ref_428617.mem array_a.mem
	
# We elaborate with yosys, which succedds:

yosys -s mmult_accel.ys | tee yosys_mmult_accel.log
