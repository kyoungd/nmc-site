import { prisma } from './prisma.js'

// User operations
export const userOperations = {
  async findByClerkId(clerkUserId) {
    return prisma.user.findUnique({
      where: { clerkUserId },
      include: {
        memberships: {
          include: {
            business: true
          }
        }
      }
    })
  },

  async create(data) {
    return prisma.user.create({
      data,
      include: {
        memberships: {
          include: {
            business: true
          }
        }
      }
    })
  },

  async update(id, data) {
    return prisma.user.update({
      where: { id },
      data,
      include: {
        memberships: {
          include: {
            business: true
          }
        }
      }
    })
  }
}

// Business operations
export const businessOperations = {
  async findById(id) {
    return prisma.business.findUnique({
      where: { id },
      include: {
        ownersAdmins: {
          include: {
            user: true
          }
        },
        employees: true,
        numbers: true,
        contacts: true,
        entitlement: true
      }
    })
  },

  async create(data) {
    return prisma.business.create({
      data,
      include: {
        ownersAdmins: {
          include: {
            user: true
          }
        }
      }
    })
  },

  async findByUserId(userId) {
    return prisma.business.findMany({
      where: {
        ownersAdmins: {
          some: {
            userId
          }
        }
      },
      include: {
        ownersAdmins: {
          include: {
            user: true
          }
        }
      }
    })
  }
}

// Conversation operations
export const conversationOperations = {
  async findByBusinessId(businessId, { page = 1, limit = 20 } = {}) {
    const skip = (page - 1) * limit

    return prisma.conversation.findMany({
      where: { businessId },
      include: {
        contact: true,
        messages: {
          orderBy: { createdAt: 'asc' }
        }
      },
      orderBy: { openedAt: 'desc' },
      skip,
      take: limit
    })
  },

  async findById(id) {
    return prisma.conversation.findUnique({
      where: { id },
      include: {
        contact: true,
        messages: {
          include: {
            employee: true
          },
          orderBy: { createdAt: 'asc' }
        }
      }
    })
  },

  async create(data) {
    return prisma.conversation.create({
      data,
      include: {
        contact: true,
        messages: true
      }
    })
  }
}

// Message operations
export const messageOperations = {
  async create(data) {
    return prisma.message.create({
      data,
      include: {
        employee: true,
        conversation: {
          include: {
            contact: true
          }
        }
      }
    })
  },

  async findByConversationId(conversationId) {
    return prisma.message.findMany({
      where: { conversationId },
      include: {
        employee: true
      },
      orderBy: { createdAt: 'asc' }
    })
  }
}

// Contact operations
export const contactOperations = {
  async findOrCreate(businessId, e164) {
    const existing = await prisma.contact.findUnique({
      where: {
        businessId_e164: {
          businessId,
          e164
        }
      }
    })

    if (existing) {
      return existing
    }

    return prisma.contact.create({
      data: {
        businessId,
        e164
      }
    })
  },

  async optOut(businessId, e164) {
    return prisma.contact.update({
      where: {
        businessId_e164: {
          businessId,
          e164
        }
      },
      data: {
        optOutAt: new Date()
      }
    })
  }
}

// Appointment operations
export const appointmentOperations = {
  async findByBusinessId(businessId, { start, end } = {}) {
    const where = { businessId }

    if (start || end) {
      where.start = {}
      if (start) where.start.gte = start
      if (end) where.start.lte = end
    }

    return prisma.appointment.findMany({
      where,
      include: {
        contact: true,
        employee: true
      },
      orderBy: { start: 'asc' }
    })
  },

  async create(data) {
    return prisma.appointment.create({
      data,
      include: {
        contact: true,
        employee: true
      }
    })
  },

  async update(id, data) {
    return prisma.appointment.update({
      where: { id },
      data,
      include: {
        contact: true,
        employee: true
      }
    })
  }
}