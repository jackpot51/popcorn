# popcorn - a security research project for Pop!\_OS

The goal of this project is to improve the security of data stored on Pop!\_OS
systems beyond what is possible with the current disk encryption model. **This
project is still a work in progress, and it is recommended to wait for
a release before using it.**

There are a few requirements for such a system:

- ROOTKIT-RESISTANT: The system can be physically controlled by a third party
  for a moderate amount of time without them being able to install code that
  would allow for data exfiltration. This is often referred to as the
  "evil maid attack". This situation happens whenever the user temporarily
  leaves the system. The system could be left on and locked, on and unlocked,
  or off.
- STRONG ENCRYPTION: The system can be physically controlled by a third party
  for a very long amount of time with minimal threat of data being exfiltrated.
  This includes the "cold boot attack" and related attacks. This situation
  happens when the system is lost or stolen. Again, the system could be left on
  and locked, on and unlocked, or off.
- UPGRADEABLE: The system, including both firmware and software, can be
  upgraded regularly with minimal user interaction. No code is perfect, and
  building a fortress but never being able to patch the holes will inevitably
  lead to data exfiltration.
- USABLE: The system must make it easy for most end users to achieve the best
  security configuration. Requiring users to understand cryptography is doomed
  to failure.
- USER-OWNED: The system firmware and software can be replaced by a user. This
  is to ensure the hardware can be owned by the end user, even in the event of
  the hardware vendor going bankrupt, the end user forgetting passwords, or the
  device being sold to another user. There can be restrictions imposed to
  ensure that other requirements are met.
- VENDOR NEUTRAL: The solution must be able to be deployed on a wide array of
  hardware with no vendor-specific hardware requirements or favoritism for one
  particular hardware vendor.

Out of scope:

- SOCIAL ENGINEERING: At any time, the user could be tricked or coerced into
  providing required secrets. Fortifying oneself inside a secret island bunker
  may help, or may draw the attention of even larger adversaries.
- TOTAL LOSS: Complete destruction of user data is always possible and should
  be solved with redundant backups, which are ideally also secured with a
  similar mechanism.

There are some technologies that can help provide these requirements. The use
of coreboot, Linux, and other open source projects improves the ability of the
end user to own their hardware. A Trusted Platform Module (TPM) can be
leveraged to measure the boot process and prevent rootkits. Secure Boot can be
used to verify the kernel, drivers, and software that are used to unlock the
disk. Full disk encryption can be used, and a sane configuration can prevent
disk contents or the encryption key from being leaked.

Technically speaking, all the pieces are there. Unfortunately, it is the case
that actually setting up all these pieces in the most secure way is very
difficult for the end user. Furthermore, if they rely on another party, like
the hardware manufacturer, to set them up, it may be easy for this manufacturer
to bypass the protections with back doors.

This is where this research project comes in: how do we take the industry
standard security mechanisms already present in most modern computers, and
chain them together in a way that the end user controls the result and also
understands it?

I will go into more detail, also considering related projects like
[BitLocker](https://docs.microsoft.com/en-us/windows/security/information-protection/bitlocker/bitlocker-overview),
[Boot Guard](https://edk2-docs.gitbook.io/understanding-the-uefi-secure-boot-chain/secure_boot_chain_in_uefi/intel_boot_guard),
[Heads](https://osresearch.net/), [safeboot](https://safeboot.dev/), and
[vboot](https://doc.coreboot.org/security/vboot/index.html) later. There are
also hundreds of research papers out there on this exact topic, and I have
already read hundreds of pages of dense research just to become comfortable
with this topic. Condensing all this into one project that best meets our
requirements will be difficult, and may even be impossible without compromising
one requirement or another.
