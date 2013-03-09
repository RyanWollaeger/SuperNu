      module gasgridmod
c     ---------------
      IMPLICIT NONE
************************************************************************
* gas grid structure
************************************************************************
      integer,parameter :: gas_nelem=30
      integer,parameter :: gas_ini56=-1, gas_ico56=-2 !positions in mass0fr and natom1fr arrays
c
c-- conversion factors and constants
      REAL*8 :: gas_vout      !outer boundary velocity
      REAL*8 :: gas_xi2beta   !converts position in rcell length units to v/c
      REAL*8 :: gas_cellength !converts rcell length units to cm
      REAL*8 :: gas_dxwin     !travel 'time' window
c
      integer :: gas_ncg=0    !number of gas_grid cells
c
      integer :: gas_npacket  !total # packets to be generated
      integer :: gas_mpacket  !# packets to be generated on the current mpi rank
c
c
c-- primary gas grid, available on all ranks
      type gas_primary
c-- energy
       REAL*8 :: enabs_c    !counted absorbed energy
       REAL*8 :: enabs_e    !estimated absorbed energy
c-- scattering
       REAL*8 :: sig        !Thomson scattering coeff
c-- gamma opacity
       REAL*8 :: capgam     !Thomson scattering coeff
      end type gas_primary
      type(gas_primary),allocatable :: gas_vals(:)  !(gas_ncg)
c
c-- line opacity
      REAL*8,allocatable :: gas_wl(:) !(in_nwlg) wavelength grid
      REAL*8,allocatable :: gas_dwl(:) !(in_nwlg) wavelength grid bin width
      real*4,allocatable :: gas_cap(:,:) !(gas_ncg,in_nwlg) Line+Cont extinction coeff
c
c
c-- secondary gas grid, available on master rank only
      type gas_secondary
!tempkev       REAL*8 :: temp       !gcell temperature
       REAL*8 :: volr       !gcell volume [rout=1 units]
!dr3_34pi       REAL*8 :: vol        !gcell volume [cm^3]
       REAL*8 :: volcrp     !effective volume (of linked rgrid cells) [cm^3]
!rho       REAL*8 :: mass       !gcell mass
       REAL*8 :: mass0fr(-2:gas_nelem) = 0d0  !initial mass fractions (>0:stable+unstable, -1:ni56, -2:co56, 0:container for unused elements)
       REAL*8 :: natom      !gcell # atoms
       REAL*8 :: natom1fr(-2:gas_nelem) = 0d0 !current natom fractions (>0:stable+unstable, -1:ni56, -2:co56, 0:container for unused elements)
       REAL*8 :: natom0fr(-2:2) = 0d0     !initial natom fractions (0,1,2:stable fe/co/ni, -1:ni56, -2:co56)
       REAL*8 :: nelec=1d0  !gcell # electrons per atom
c-- opacity invalidity flag
       LOGICAL :: opdirty=.true. !opacity needs recalculation
c-- energy reservoir
       REAL*8 :: engdep     !energy deposited by gamma rays
      end type gas_secondary
      type(gas_secondary),allocatable :: gas_vals2(:) !(gas_ncg)
c
c-- temperature structure history
      REAL*8,allocatable :: gas_temphist(:,:) !(gas_ncg,tim_ntim)
c
      save
c
      contains
c
c
      subroutine gasgrid_alloc(ncg_in,ntim_in)
c     --------------------------------------
      use inputparmod, only:in_nwlg,in_niwlem,in_ndim
      IMPLICIT NONE
      integer,intent(in) :: ncg_in,ntim_in
************************************************************************
* allocate gas_vals variables
************************************************************************
      integer :: icgbyte
      character(28) :: labl
c
c--
      gas_ncg = ncg_in
      write(6,*) '# cells in gas_vals          :',gas_ncg
c
c-- gcell size
      allocate(gas_vals(1))
      icgbyte = sizeof(gas_vals) + 4*in_nwlg + 8*3 !gas_vals + gas_cap + enostor+enabs_e+enabs_c
      deallocate(gas_vals)
c
c-- print used memory size
      if(in_ndim==1) then
       labl = 'allocate 1D sphericl gas_vals:'
      elseif(in_ndim==2) then
       labl = 'allocate 2D cylindr gas_vals :'
      endif
      write(6,'(1x,a,i10,"kB",i7,"MB")') labl,
     &   nint((icgbyte*gas_ncg)/1024.),nint((icgbyte*gas_ncg)/1024.**2)
c
c-- allocate
      allocate(gas_vals(gas_ncg))       !primary gas grid
      allocate(gas_cap(gas_ncg,in_nwlg))
      allocate(gas_wl(in_nwlg))
      allocate(gas_vals2(gas_ncg))      !secondary gas grid
      allocate(gas_dwl(in_nwlg)) !wavelength grid bin width
      allocate(gas_temphist(gas_ncg,ntim_in))
      end subroutine gasgrid_alloc
c
      end module gasgridmod
