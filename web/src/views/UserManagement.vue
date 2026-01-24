<template>
  <div class="user-management-container">
    <a-card title="User Management" :bordered="false">
      <template #extra>
        <a-button type="primary" size="small" @click="handleAdd">
          <PlusOutlined />
          Add User
        </a-button>
      </template>

      <a-table
        :columns="columns"
        :data-source="users"
        :loading="loading"
        row-key="id"
        size="small"
      >
        <template #bodyCell="{ column, record }">
          <template v-if="column.key === 'role'">
            <a-tag :color="record.role === 'admin' ? 'red' : 'blue'">
              {{ record.role }}
            </a-tag>
          </template>
          <template v-if="column.key === 'status'">
            <a-tag :color="record.status === 'active' ? 'success' : 'default'">
              {{ record.status }}
            </a-tag>
          </template>
          <template v-if="column.key === 'action'">
            <a-space>
              <a-button size="small" @click="handleEdit(record)">
                <EditOutlined />
              </a-button>
              <a-popconfirm
                title="Are you sure you want to delete this user?"
                @confirm="handleDelete(record.id)"
              >
                <a-button size="small" danger>
                  <DeleteOutlined />
                </a-button>
              </a-popconfirm>
            </a-space>
          </template>
        </template>
      </a-table>
    </a-card>

    <!-- User Modal -->
    <a-modal
      v-model:open="showModal"
      :title="editingUser ? 'Edit User' : 'Add User'"
      @ok="handleSave"
      :confirmLoading="saving"
    >
      <a-form :model="form" layout="vertical" ref="formRef">
        <a-form-item
          label="Username"
          name="username"
          :rules="[{ required: true, message: 'Please enter username' }]"
        >
          <a-input v-model:value="form.username" :disabled="!!editingUser" />
        </a-form-item>
        <a-form-item
          label="Email"
          name="email"
          :rules="[{ required: true, type: 'email', message: 'Please enter a valid email' }]"
        >
          <a-input v-model:value="form.email" />
        </a-form-item>
        <a-form-item label="Display Name" name="display_name">
          <a-input v-model:value="form.display_name" />
        </a-form-item>
        <a-form-item
          label="Password"
          name="password"
          :rules="[{ required: !editingUser, message: 'Please enter password', min: 8 }]"
        >
          <a-input-password v-model:value="form.password" :placeholder="editingUser ? 'Leave blank to keep current' : ''" />
        </a-form-item>
        <a-form-item label="Role" name="role" :rules="[{ required: true }]">
          <a-select v-model:value="form.role">
            <a-select-option value="user">User</a-select-option>
            <a-select-option value="admin">Admin</a-select-option>
          </a-select>
        </a-form-item>
        <a-form-item label="Status" name="status" v-if="editingUser">
          <a-select v-model:value="form.status">
            <a-select-option value="active">Active</a-select-option>
            <a-select-option value="disabled">Disabled</a-select-option>
          </a-select>
        </a-form-item>
      </a-form>
    </a-modal>
  </div>
</template>

<script setup>
import { ref, reactive, onMounted } from 'vue'
import { message } from 'ant-design-vue'
import { PlusOutlined, EditOutlined, DeleteOutlined } from '@ant-design/icons-vue'
import { getUsers, createUser, updateUser, deleteUser } from '../api/users'

const loading = ref(false)
const saving = ref(false)
const users = ref([])
const showModal = ref(false)
const editingUser = ref(null)
const formRef = ref(null)

const form = reactive({
  username: '',
  email: '',
  display_name: '',
  password: '',
  role: 'user',
  status: 'active'
})

const columns = [
  { title: 'Username', dataIndex: 'username', key: 'username' },
  { title: 'Email', dataIndex: 'email', key: 'email' },
  { title: 'Display Name', dataIndex: 'display_name', key: 'display_name' },
  { title: 'Role', dataIndex: 'role', key: 'role' },
  { title: 'Status', dataIndex: 'status', key: 'status' },
  { title: 'Action', key: 'action', width: 150 }
]

onMounted(() => {
  loadUsers()
})

const loadUsers = async () => {
  loading.value = true
  try {
    const response = await getUsers()
    users.value = response.data || response
  } catch (error) {
    message.error('Failed to load users')
  } finally {
    loading.value = false
  }
}

const handleAdd = () => {
  editingUser.value = null
  Object.assign(form, {
    username: '',
    email: '',
    display_name: '',
    password: '',
    role: 'user',
    status: 'active'
  })
  showModal.value = true
}

const handleEdit = (user) => {
  editingUser.value = user
  Object.assign(form, {
    username: user.username,
    email: user.email,
    display_name: user.display_name,
    password: '',
    role: user.role,
    status: user.status
  })
  showModal.value = true
}

const handleSave = async () => {
  try {
    await formRef.value.validate()
    saving.value = true
    
    if (editingUser.value) {
      await updateUser(editingUser.value.id, form)
      message.success('User updated successfully')
    } else {
      await createUser(form)
      message.success('User created successfully')
    }
    
    showModal.value = false
    loadUsers()
  } catch (error) {
    if (error.errorFields) return // Validation failed
    message.error(error.response?.data?.error || 'Failed to save user')
  } finally {
    saving.value = false
  }
}

const handleDelete = async (id) => {
  try {
    await deleteUser(id)
    message.success('User deleted successfully')
    loadUsers()
  } catch (error) {
    message.error(error.response?.data?.error || 'Failed to delete user')
  }
}
</script>

<style scoped>
.user-management-container {
  padding: 16px;
}

@media (max-width: 768px) {
  .user-management-container {
    padding: 8px;
  }
  
  .user-management-container :deep(.ant-card-head) {
    padding: 0 12px;
  }
  
  .user-management-container :deep(.ant-table) {
    font-size: 12px;
  }
  
  .user-management-container :deep(.ant-table-thead > tr > th),
  .user-management-container :deep(.ant-table-tbody > tr > td) {
    padding: 8px 6px !important;
  }
  
  .user-management-container :deep(.ant-btn) {
    padding: 2px 6px;
    font-size: 11px;
  }
  
  .user-management-container :deep(.ant-tag) {
    font-size: 10px;
    padding: 0 4px;
  }
}
</style>
