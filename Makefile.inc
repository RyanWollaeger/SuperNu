########################################################################
# GENERAL RULES
########################################################################
%: %.o
	$(FC) $(FCFLAGS) -o $@ $^ $(LDFLAGS)

#-- fixed format
%.o: %.f
	$(FC) $(FCFLAGS) $(FCFLAGS_FF) -c $<

%.o: %.f90
	$(FC) $(FCFLAGS) -c $<

%.mod: ../%.mod
	@cp -pf $< $@