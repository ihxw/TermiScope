<template>
  <div class="user-management-container">
    <a-card :title="t('user.title')" :bordered="false">
      <template #extra>
        <a-button type="primary" size="small" @click="handleAdd">
          <PlusOutlined />
          {{ t('user.addUser') }}
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
              {{ t(`user.${record.role}`) }}
            </a-tag>
          </template>
          <template v-if="column.key === 'status'">
            <a-tag :color="record.status === 'active' ? 'success' : 'default'">
              {{ t(`user.${record.status}`) }}
            </a-tag>
          </template>
          <template v-if="column.key === 'action'">
            <a-space>
              <a-button size="small" @click="handleEdit(record)">
                <EditOutlined />
              </a-button>
              <a-popconfirm
                :title="t('user.deleteConfirm')"
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
      :title="editingUser ? t('user.editUser') : t('user.addUser')"
      @ok="handleSave"
      :confirmLoading="saving"
    >
      <a-form :model="form" layout="vertical" ref="formRef">
        <a-form-item
          :label="t('user.username')"
          name="username"
          :rules="[{ required: true, message: t('user.enterUsername') }]"
        >
          <a-input v-model:value="form.username" :disabled="!!editingUser" />
        </a-form-item>
        <a-form-item
          :label="t('user.email')"
          name="email"
          :rules="[{ required: true, type: 'email', message: t('user.enterValidEmail') }]"
        >
          <a-input v-model:value="form.email" />
        </a-form-item>
        <a-form-item :label="t('user.displayName')" name="display_name">
          <a-input v-model:value="form.display_name" />
        </a-form-item>
        <a-form-item
          :label="t('auth.password')"
          name="password"
          :rules="[{ required: !editingUser, message: t('user.enterPassword'), min: 8 }]"
        >
          <a-input-password v-model:value="form.password" :placeholder="editingUser ? t('user.leaveBlankKeepCurrent') : ''" />
        </a-form-item>
        <a-form-item :label="t('user.role')" name="role" :rules="[{ required: true }]">
          <a-select v-model:value="form.role">
            <a-select-option value="user">{{ t('user.user') }}</a-select-option>
            <a-select-option value="admin">{{ t('user.admin') }}</a-select-option>
          </a-select>
        </a-form-item>
        <a-form-item :label="t('user.status')" name="status" v-if="editingUser">
          <a-select v-model:value="form.status">
            <a-select-option value="active">{{ t('user.active') }}</a-select-option>
            <a-select-option value="disabled">{{ t('user.disabled') }}</a-select-option>
          </a-select>
        </a-form-item>
      </a-form>
    </a-modal>
  </div>
</template>

<script setup>
import { ref, reactive, onMounted, computed } from 'vue'
import { message } from 'ant-design-vue'
import { PlusOutlined, EditOutlined, DeleteOutlined } from '@ant-design/icons-vue'
import { getUsers, createUser, updateUser, deleteUser } from '../api/users'
import { useI18n } from 'vue-i18n'

const { t } = useI18n()

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

const columns = computed(() => [
  { title: t('user.username'), dataIndex: 'username', key: 'username' },
  { title: t('user.email'), dataIndex: 'email', key: 'email' },
  { title: t('user.displayName'), dataIndex: 'display_name', key: 'display_name' },
  { title: t('user.role'), dataIndex: 'role', key: 'role' },
  { title: t('user.status'), dataIndex: 'status', key: 'status' },
  { title: t('user.action'), key: 'action', width: 150 }
])

onMounted(() => {
  loadUsers()
})

const loadUsers = async () => {
  loading.value = true
  try {
    const response = await getUsers()
    users.value = response.data || response
  } catch (error) {
    message.error(t('user.loadFailed'))
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
    
    // Clone form to avoid mutating UI state
    const submitData = { ...form }
    
    // Hash password if present
    if (submitData.password) {
      submitData.password = submitData.password
    } else if (!editingUser.value) {
        // Should be caught by validation, but just in case
        return
    } else {
        // Editing and password empty -> remove it so it doesn't update
        delete submitData.password
    }

    if (editingUser.value) {
      await updateUser(editingUser.value.id, submitData)
      message.success(t('user.updatedSuccess'))
    } else {
      await createUser(submitData)
      message.success(t('user.createdSuccess'))
    }
    
    showModal.value = false
    loadUsers()
  } catch (error) {
    if (error.errorFields) return // Validation failed
    message.error(error.response?.data?.error || t('user.saveFailed'))
  } finally {
    saving.value = false
  }
}

const handleDelete = async (id) => {
  try {
    await deleteUser(id)
    message.success(t('user.userDeleted'))
    loadUsers()
  } catch (error) {
    message.error(error.response?.data?.error || t('user.deleteFailed'))
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
